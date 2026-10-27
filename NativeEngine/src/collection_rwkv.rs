//! Mobile review coordinator using the fork's canonical history/input-row RPCs.
//! Recurrent state is derived; SQLite, IDs, revlogs and presets stay authoritative.
use crate::full_backend::call_backend;
use anki::{
    backend::Backend,
    rwkv::{ModelKind, ReviewInput, ReviewState, RwkvRuntime, StatePrecision},
};
use blake2::{
    Blake2bVar,
    digest::{Update, VariableOutput},
};
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    sync::{LazyLock, Mutex},
};
struct Cached {
    key: String,
    identity: Value,
    runtime: RwkvRuntime,
}
static RUNTIMES: LazyLock<Mutex<HashMap<u64, Cached>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
#[derive(Default)]
struct ReviewSession {
    deck: Value,
    queue: Value,
    answered: u32,
    pending_answer: Option<i64>,
    restore_card: Option<i64>,
    frames: HashMap<i64, AnswerFrame>,
    redo_frames: HashMap<i64, AnswerFrame>,
}
struct AnswerFrame {
    card: i64,
}
struct CandidateCache {
    key: Value,
    rows: HashMap<i64, Value>,
    dirty: Vec<i64>,
}
static CANDIDATES: LazyLock<Mutex<HashMap<u64, CandidateCache>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
static SESSIONS: LazyLock<Mutex<HashMap<u64, ReviewSession>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
// Reviewer-local state, like the desktop's _rwkv_synthetic_answer_states.
// Exact revlog IDs prevent a recent undone answer matching an older row.
static SYNTHETIC_ANSWERS: LazyLock<Mutex<HashMap<u64, HashMap<i64, i64>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
fn rpc(backend: &Backend, method: &str, input: Value) -> Result<Value, String> {
    call_backend(backend, "BackendSchedulerService", method, input)
}
fn int(v: &Value) -> i64 {
    v.as_i64()
        .or_else(|| v.as_str().and_then(|s| s.parse().ok()))
        .unwrap_or(0)
}
fn optional(v: &Value) -> Option<i64> {
    if v.is_null() { None } else { Some(int(v)) }
}
fn stable_preset_id(s: &str) -> i64 {
    if let Ok(id) = s.parse() {
        return id;
    }
    let mut hasher = Blake2bVar::new(8).unwrap();
    hasher.update(s.as_bytes());
    let mut digest = [0u8; 8];
    hasher.finalize_variable(&mut digest).unwrap();
    (u64::from_be_bytes(digest) & i64::MAX as u64) as i64
}
fn history_input(v: &Value) -> ReviewInput {
    ReviewInput {
        card_id: int(&v["cardId"]),
        note_id: optional(&v["noteId"]),
        deck_id: optional(&v["deckId"]),
        preset_id: optional(&v["presetId"]),
        is_query: false,
        ease: Some(int(&v["ease"]) as u8),
        duration_millis: Some(int(&v["durationMillis"])),
        card_type: Some(int(&v["cardType"])),
        day_offset: Some(int(&v["dayOffset"])),
        current_elapsed_days: Some(int(&v["elapsedDays"])),
        current_elapsed_seconds: Some(int(&v["elapsedSeconds"])),
        target_retentions: [None; 4],
        enforce_grade_order: true,
    }
}
fn query_input(v: &Value, latest: Option<&Value>, synthetic_answer: Option<i64>) -> ReviewInput {
    let kind = match v["currentNormalStateKind"].as_str().unwrap_or("") {
        "new" => 0,
        "learning" => 1,
        "review" => 2,
        "relearning" => 3,
        _ => int(&v["cardType"]),
    };
    let mut kind = if v["currentStateKind"] == "filtered" {
        4
    } else {
        kind
    };
    // Match the fork's synthetic same-day review context. A card may be
    // stored as Review after learning while the neural event is Filtered.
    if kind == 2 {
        if let Some(previous) = latest.filter(|p| int(&p["dayOffset"]) == int(&v["dayOffset"])) {
            kind = match (int(&previous["reviewKind"]), int(&previous["ease"])) {
                (1, 1) | (2, 1 | 2) => 3,
                (0..=2, _) => 4,
                (3, _) if synthetic_answer == Some(int(&previous["reviewId"])) => 4,
                _ => kind,
            };
        }
    }
    let retention = v["targetRetention"].as_f64().unwrap_or(0.9) as f32;
    ReviewInput {
        card_id: int(&v["cardId"]),
        note_id: optional(&v["noteId"]),
        deck_id: optional(&v["deckId"]),
        preset_id: v["presetId"].as_str().map(stable_preset_id),
        is_query: true,
        ease: None,
        duration_millis: None,
        card_type: Some(kind),
        day_offset: Some(int(&v["dayOffset"])),
        current_elapsed_days: optional(&v["currentElapsedDays"]),
        current_elapsed_seconds: optional(&v["currentElapsedSeconds"]),
        target_retentions: [Some(retention); 4],
        enforce_grade_order: v["enforceGradeOrder"].as_bool().unwrap_or(true),
    }
}
fn predict(runtime: &mut RwkvRuntime, input: &ReviewInput) -> Result<Value, String> {
    let state = runtime.warm_up_state(input);
    let output = runtime
        .review(
            input.clone(),
            ReviewState {
                card: state.card.as_deref(),
                note: state.note.as_deref(),
                deck: state.deck.as_deref(),
                preset: state.preset.as_deref(),
                global: state.global.as_deref(),
            },
        )
        .map_err(|e| e.to_string())?;
    let review_kind = match input.card_type.unwrap_or(2) {
        0 | 1 => 0,
        2 => 1,
        3 => 2,
        _ => 3,
    };
    Ok(
        json!({"retrievability":output.retrievability,"intervals":output.intervals,"s90s":output.s90s,"reviewKind":review_kind,
            "buttonProbabilities":output.button_probabilities,"curveRetrievability":output.curve_retrievability,
            "currentInterval":output.current_interval,"currentS90":output.current_s90}),
    )
}
pub fn prepare(handle: u64, backend: &Backend, request: Value) -> Result<Value, String> {
    let deck = request["deckId"].clone();
    let model = request["model"].as_str().unwrap_or("sm56");
    let path = request["path"].as_str().ok_or("Missing RWKV weights")?;
    let precision = request["precision"]
        .as_str()
        .unwrap_or("cards_int4_notes_int8");
    let selected = call_backend(
        backend,
        "BackendDecksService",
        "GetDeck",
        json!({"did":deck}),
    )?;
    let selected_config = if selected["normal"].is_null() {
        Value::Null
    } else {
        call_backend(
            backend,
            "BackendDeckConfigService",
            "GetDeckConfig",
            json!({"dcid":selected["normal"]["configId"]}),
        )?
    };
    let gather = &selected_config["config"]["newCardGatherPriority"];
    let before_next = gather
        .as_str()
        .is_some_and(|s| s.contains("RETRIEVABILITY"))
        || matches!(gather.as_i64(), Some(6 | 7));
    let mut rows = rpc(
        backend,
        "RwkvReviewInputRowsForDeckReviewQueue",
        json!({"deckId":deck,"includeNewCards":before_next}),
    )?;
    let timing = rpc(backend, "SchedTimingToday", json!({}))?;
    let (pending, will_refresh) = {
        let sessions = SESSIONS.lock().map_err(|_| "Review session unavailable")?;
        if let Some(session) = sessions.get(&handle).filter(|s| s.deck == deck) {
            let config = &selected_config["config"];
            let count = int(&session.queue["newCount"])
                + int(&session.queue["learningCount"])
                + int(&session.queue["reviewCount"]);
            let last_review = int(&session.queue["reviewCount"]) == 1
                && session.queue["cards"][0]["queue"] == "REVIEW";
            (
                session.pending_answer,
                session.pending_answer.is_none()
                    || config["rwkvReviewInstantOrderEnabled"] != true
                    || session.answered % int(&config["rwkvReviewRefreshInterval"]).max(1) as u32
                        == 0
                    || count <= 1
                    || last_review,
            )
        } else {
            (None, true)
        }
    };
    // The desktop retains ordinary candidate input rows for a scheduler day,
    // refreshing answered/dirty cards rather than aging every row on each tap.
    // Explicit-ID refresh also retains eligible learning/relearning candidates.
    let cache_key = json!({"deck":deck,"day":timing["daysElapsed"],"configuration":request["configuration"],"selected":selected_config});
    {
        let mut candidates = CANDIDATES
            .lock()
            .map_err(|_| "Candidate cache unavailable")?;
        let cached = candidates.entry(handle).or_insert_with(|| CandidateCache {
            key: cache_key.clone(),
            rows: rows["rows"]
                .as_array()
                .into_iter()
                .flatten()
                .map(|r| (int(&r["cardId"]), r.clone()))
                .collect(),
            dirty: vec![],
        });
        if cached.key != cache_key {
            *cached = CandidateCache {
                key: cache_key,
                rows: rows["rows"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .map(|r| (int(&r["cardId"]), r.clone()))
                    .collect(),
                dirty: vec![],
            };
        }
        let mut ids: Vec<i64> = if will_refresh {
            cached.dirty.clone()
        } else {
            pending.into_iter().collect()
        };
        ids.sort_unstable();
        ids.dedup();
        let mut working = cached.rows.clone();
        if !ids.is_empty() {
            let refreshed = rpc(
                backend,
                "RwkvReviewInputRowsForCards",
                json!({"cardIds":ids.iter().map(ToString::to_string).collect::<Vec<_>>(),"includeNewCards":before_next}),
            )?;
            for id in ids {
                working.remove(&id);
            }
            for row in refreshed["rows"].as_array().into_iter().flatten() {
                working.insert(int(&row["cardId"]), row.clone());
            }
        }
        if will_refresh {
            cached.rows = working.clone();
            cached.dirty.clear();
        }
        let mut values = working.into_iter().collect::<Vec<_>>();
        values.sort_by_key(|(id, _)| *id);
        rows["rows"] = json!(values.into_iter().map(|(_, row)| row).collect::<Vec<_>>());
    }
    let mut ids = serde_json::Map::new();
    let card_ids = call_backend(
        backend,
        "BackendSearchService",
        "SearchCards",
        json!({"search":""}),
    )?;
    let presets = rpc(
        backend,
        "GetFsrsPresetIdsForCards",
        json!({"cids":card_ids["ids"]}),
    )?;
    for row in presets["items"].as_array().into_iter().flatten() {
        if let Some(id) = row["presetId"].as_str() {
            ids.insert(id.into(), json!(stable_preset_id(id).to_string()));
        }
    }
    let history = rpc(
        backend,
        "RwkvHistoricalReviewInputs",
        json!({"history":{"dynamicPresetReplay":request["dynamicPresetReplay"].as_bool().unwrap_or(false),"stablePresetIds":ids}}),
    )?;
    let identity = history["metadata"]["identity"].clone();
    let key = format!("{model}:{path}:{precision}");
    let mut caches = RUNTIMES.lock().map_err(|_| "RWKV runtime unavailable")?;
    let cached = caches.get(&handle);
    if cached.is_none_or(|c| c.key != key || c.identity != identity) {
        let mut runtime = RwkvRuntime::load_with_precision(
            path.into(),
            0.9,
            36500,
            StatePrecision::parse(precision).map_err(|e| e.to_string())?,
            ModelKind::parse(model).map_err(|e| e.to_string())?,
        )
        .map_err(|e| e.to_string())?;
        runtime
            .warm_up_reviews(
                history["reviews"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .map(history_input)
                    .collect(),
                false,
            )
            .map_err(|e| e.to_string())?;
        caches.insert(
            handle,
            Cached {
                key,
                identity,
                runtime,
            },
        );
    }
    let runtime = &mut caches.get_mut(&handle).unwrap().runtime;
    let history_rows = history["reviews"].as_array().cloned().unwrap_or_default();
    let mut previous = HashMap::new();
    for (i, row) in history_rows.iter().enumerate() {
        previous.insert(int(&row["cardId"]), i);
    }
    let mut scores = vec![];
    let mut predictions = serde_json::Map::new();
    for row in rows["rows"].as_array().into_iter().flatten() {
        // Desktop candidate scoring uses the backend row's ordinary state.
        // Synthetic same-day state is applied only to the displayed card.
        let mut input = query_input(row, None, None);
        let intervening = previous
            .get(&input.card_id)
            .map(|i| history_rows.len() - i - 1)
            .unwrap_or(history_rows.len());
        // Candidate eligibility uses the row's configured target on desktop.
        // Grade-dependent dynamic targets belong to the displayed card below.
        let target_retention = row["targetRetention"].as_f64().unwrap_or(0.9);
        input.target_retentions = [Some(target_retention as f32); 4];
        let output = predict(runtime, &input)?;
        scores.push(json!({"cardId":input.card_id.to_string(),"retrievability":output["retrievability"],"interveningReviews":intervening,"targetRetention":target_retention}));
        predictions.insert(input.card_id.to_string(), output);
    }
    // Desktop normally shows the next retained card before refreshing scores.
    // Replacing the map first would select a different card at that boundary.
    let mut sessions = SESSIONS.lock().map_err(|_| "Review session unavailable")?;
    let session = sessions.entry(handle).or_default();
    if session.deck != deck {
        *session = ReviewSession {
            deck: deck.clone(),
            ..Default::default()
        };
    }
    let mut refresh = true;
    #[cfg(feature = "validation-comparison")]
    let previous_queue = session.queue.clone();
    let mut preserve = Value::Null;
    let mut displayed_queue = Value::Null;
    let mut refreshed_counts = Value::Null;
    let instant = selected_config["config"]["rwkvReviewInstantOrderEnabled"] == true;
    if let Some(answered_card) = session.pending_answer.take() {
        let card = call_backend(
            backend,
            "BackendCardsService",
            "GetCard",
            json!({"cid":answered_card.to_string()}),
        )?;
        let card_deck = call_backend(
            backend,
            "BackendDecksService",
            "GetDeck",
            json!({"did":card["deckId"]}),
        )?;
        let config = call_backend(
            backend,
            "BackendDeckConfigService",
            "GetDeckConfig",
            json!({"dcid":card_deck["normal"]["configId"]}),
        )?;
        let config = &config["config"];
        if config["rwkvReviewInstantOrderEnabled"] == true {
            rpc(
                backend,
                "UpdateRwkvReviewQueueInterveningReviews",
                json!({"deckId":deck,"items":scores.iter().map(|s|json!({"cardId":s["cardId"],"interveningReviews":s["interveningReviews"]})).collect::<Vec<_>>()}),
            )?;
            let count = int(&session.queue["newCount"])
                + int(&session.queue["learningCount"])
                + int(&session.queue["reviewCount"]);
            let last_review = int(&session.queue["reviewCount"]) == 1
                && session.queue["cards"][0]["queue"] == "REVIEW";
            let interval = int(&config["rwkvReviewRefreshInterval"]).max(1) as u32;
            let due = session.answered % interval == 0;
            refresh = due || count <= 1 || last_review;
            if !refresh {
                let score = scores.iter().find(|s| int(&s["cardId"]) == answered_card);
                let mut patch = json!({"deckId":deck,"cardId":answered_card.to_string()});
                if let Some(score) = score {
                    patch["score"] = score.clone();
                }
                rpc(backend, "PatchAnsweredCardRwkvReviewQueueScore", patch)?;
            } else if due && count > 1 && !last_review && !before_next {
                displayed_queue = rpc(backend, "GetQueuedCards", json!({"fetchLimit":1}))?;
                preserve = displayed_queue["cards"][0]["card"]["id"].clone();
            }
        }
    }
    if refresh {
        rpc(
            backend,
            "SetRwkvReviewQueueScores",
            json!({"deckId":deck,"scores":if instant {scores.clone()} else {vec![]}}),
        )?;
        if !preserve.is_null() {
            refreshed_counts = rpc(
                backend,
                "RebuildQueuedCardsPreservingCurrentCard",
                json!({"cid":preserve}),
            )?;
        }
    }
    if let Some(card) = session.restore_card.take() {
        rpc(
            backend,
            "RebuildQueuedCardsPreservingCurrentCard",
            json!({"cid":card.to_string()}),
        )?;
    }
    rpc(
        backend,
        "SetRwkvDeckCountScores",
        json!({"deckId":deck,"scores":if instant {scores} else {vec![]}}),
    )?;
    let mut queue = if preserve.is_null() {
        rpc(backend, "GetQueuedCards", json!({"fetchLimit":1}))?
    } else {
        // A retained learn-ahead card need not be first in the rebuilt backend
        // queue. Desktop keeps displaying its fetched card and only updates
        // counters; fetching again here would replace that displayed card.
        let mut displayed = displayed_queue.clone();
        for key in ["newCount", "learningCount", "reviewCount"] {
            displayed[key] = json!(int(&refreshed_counts[key]));
        }
        displayed
    };
    // Desktop's next refresh decision uses its displayed-card snapshot; the
    // asynchronously refreshed counters are only a UI override.
    session.queue = if displayed_queue.is_null() {
        queue.clone()
    } else {
        displayed_queue
    };
    #[cfg(feature = "validation-comparison")]
    {
        queue["comparisonQueuePolicy"] = json!({"previous":previous_queue,"answers":session.answered,"refresh":refresh,"preserve":preserve});
    }
    if let Some(current) = queue["cards"].as_array().and_then(|c| c.first()) {
        let cid = &current["card"]["id"];
        // The queue-scoring RPC intentionally selects review/new candidates.
        // The displayed card can be learning/relearning, so fetch its live row
        // independently, just as the desktop reviewer's input builder does.
        let displayed = rpc(
            backend,
            "RwkvReviewInputRowsForCards",
            json!({"cardIds":[cid],"includeNewCards":true}),
        )?;
        if let Some(row) = displayed["rows"]
            .as_array()
            .into_iter()
            .flatten()
            .find(|r| &r["cardId"] == cid)
        {
            let latest = previous.get(&int(cid)).map(|i| &history_rows[*i]);
            let synthetic_answer = SYNTHETIC_ANSWERS.lock().ok().and_then(|answers| {
                answers
                    .get(&handle)
                    .and_then(|cards| cards.get(&int(cid)))
                    .copied()
            });
            let mut input = query_input(row, latest, synthetic_answer);
            // Learning predictions use the displayed scheduler state's elapsed
            // seconds on desktop, not the candidate RPC's last-review age.
            // In learn-ahead sessions these can differ substantially.
            if input.card_type == Some(1)
                && !current["states"]["current"]["normal"]["learning"].is_null()
            {
                input.current_elapsed_seconds = Some(int(
                    &current["states"]["current"]["normal"]["learning"]["elapsedSecs"]
                ));
            }
            let preset = rpc(backend, "GetFsrsPresetForCard", json!({"cid":cid}))?;
            let retention = preset["desiredRetention"].as_f64().unwrap_or(0.9) as f32;
            input.target_retentions = [Some(retention); 4];
            if current["states"]["dynamicDesiredRetentionEnabled"] == true {
                if let Some(values) = current["states"]["dynamicDesiredRetentions"]
                    .as_array()
                    .filter(|v| v.len() == 4)
                {
                    input.target_retentions =
                        std::array::from_fn(|i| values[i].as_f64().map(|r| r as f32));
                }
            }
            let mut output = predict(runtime, &input)?;
            #[cfg(feature = "validation-comparison")]
            {
                output["comparisonInput"] = json!({"cardType":input.card_type,"dayOffset":input.day_offset,"currentElapsedDays":input.current_elapsed_days,"currentElapsedSeconds":input.current_elapsed_seconds,"targetRetentions":input.target_retentions,"enforceGradeOrder":input.enforce_grade_order});
            }
            if let Some(previous) = predictions.get(&input.card_id.to_string()) {
                output["queueReviewKind"] = previous["reviewKind"].clone();
            }
            predictions.insert(input.card_id.to_string(), output);
        }
    }
    Ok(
        json!({"predictions":predictions,"queue":queue,"historyIdentity":history["metadata"]["identity"]}),
    )
}

pub fn release(handle: u64) {
    if let Ok(mut candidates) = CANDIDATES.lock() {
        candidates.remove(&handle);
    }
    if let Ok(mut sessions) = SESSIONS.lock() {
        sessions.remove(&handle);
    }
    if let Ok(mut runtimes) = RUNTIMES.lock() {
        runtimes.remove(&handle);
    }
    if let Ok(mut answers) = SYNTHETIC_ANSWERS.lock() {
        answers.remove(&handle);
    }
}

pub fn invalidate_candidates(handle: u64) {
    if let Ok(mut candidates) = CANDIDATES.lock() {
        candidates.remove(&handle);
    }
    if let Ok(mut sessions) = SESSIONS.lock() {
        if let Some(session) = sessions.get_mut(&handle) {
            session.queue = Value::Null;
            session.pending_answer = None;
            session.restore_card = None;
        }
    }
}

/// Observation only: compiled out of the shipping library. Review execution
/// still uses the same public collection path as the iOS application.
#[cfg(feature = "validation-comparison")]
pub fn comparison_snapshot(handle: u64) -> Value {
    fn digest(bytes: &[u8]) -> String {
        let mut hasher = Blake2bVar::new(32).unwrap();
        hasher.update(bytes);
        let mut out = [0u8; 32];
        hasher.finalize_variable(&mut out).unwrap();
        out.iter().map(|b| format!("{b:02x}")).collect()
    }
    fn states(rows: Vec<(i64, Vec<u8>)>) -> Value {
        Value::Object(
            rows.into_iter()
                .map(|(id, bytes)| (id.to_string(), json!(digest(&bytes))))
                .collect(),
        )
    }
    let caches = RUNTIMES.lock().unwrap();
    let Some(cached) = caches.get(&handle) else {
        return Value::Null;
    };
    let snapshot = cached.runtime.warm_up_snapshot();
    json!({"cards": states(snapshot.card_states), "notes": states(snapshot.note_states),
        "decks": states(snapshot.deck_states), "presets": states(snapshot.preset_states),
        "global": snapshot.global_state.as_deref().map(digest)})
}

pub fn record_answer(handle: u64, backend: &Backend, input: &Value) {
    let cid = int(&input["cardId"]);
    if let Ok(mut candidates) = CANDIDATES.lock() {
        if let Some(cached) = candidates.get_mut(&handle) {
            cached.dirty.push(cid);
        }
    }
    let synthetic =
        input["rwkvReviewKind"] == 3 && !input["currentState"]["normal"]["review"].is_null();
    let latest = if synthetic {
        let query = json!({"kind":"query","sql":"select max(id) from revlog where cid = ?","args":[cid],"first_row_only":true});
        backend
            .run_db_command_bytes(&serde_json::to_vec(&query).unwrap())
            .ok()
            .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok())
            .and_then(|row| optional(&row[0][0]))
    } else {
        None
    };
    if let Ok(mut answers) = SYNTHETIC_ANSWERS.lock() {
        let cards = answers.entry(handle).or_default();
        if let Some(id) = latest {
            cards.insert(cid, id);
        } else {
            cards.remove(&cid);
        }
    }
    let status = call_backend(
        backend,
        "BackendCollectionService",
        "GetUndoStatus",
        json!({}),
    )
    .unwrap_or(Value::Null);
    if let Ok(mut sessions) = SESSIONS.lock() {
        if let Some(session) = sessions.get_mut(&handle) {
            session.answered += 1;
            session.pending_answer = Some(cid);
            session.redo_frames.clear();
            session
                .frames
                .insert(int(&status["lastStep"]), AnswerFrame { card: cid });
        }
    }
}

pub fn reconcile_undo(handle: u64, changes: &Value, redo: bool) {
    if let Ok(mut sessions) = SESSIONS.lock() {
        if let Some(session) = sessions.get_mut(&handle) {
            session.pending_answer = None;
            session.restore_card = None;
            let counter = int(&changes["counter"]);
            let frame = if redo {
                session.redo_frames.remove(&counter)
            } else {
                session.frames.remove(&counter)
            };
            if let Some(frame) = frame {
                session.restore_card = if redo { None } else { Some(frame.card) };
                session.answered = if redo {
                    session.answered + 1
                } else {
                    session.answered.saturating_sub(1)
                };
                if let Ok(mut answers) = SYNTHETIC_ANSWERS.lock() {
                    answers.entry(handle).or_default().remove(&frame.card);
                }
                if let Ok(mut candidates) = CANDIDATES.lock() {
                    if let Some(cached) = candidates.get_mut(&handle) {
                        cached.dirty.push(frame.card);
                    }
                }
                let destination = if redo {
                    &mut session.frames
                } else {
                    &mut session.redo_frames
                };
                destination.insert(int(&changes["newStatus"]["lastStep"]), frame);
            }
        }
    }
}
