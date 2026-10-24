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
fn query_input(v: &Value, latest: Option<&Value>) -> ReviewInput {
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
        json!({"retrievability":output.retrievability,"intervals":output.intervals,"s90s":output.s90s,"reviewKind":review_kind}),
    )
}
pub fn prepare(handle: u64, backend: &Backend, request: Value) -> Result<Value, String> {
    let deck = request["deckId"].clone();
    let model = request["model"].as_str().unwrap_or("sm56");
    let path = request["path"].as_str().ok_or("Missing RWKV weights")?;
    let precision = request["precision"]
        .as_str()
        .unwrap_or("cards_int4_notes_int8");
    let rows = rpc(
        backend,
        "RwkvReviewInputRowsForDeckReviewQueue",
        json!({"deckId":deck,"includeNewCards":true}),
    )?;
    let mut retention_requests = vec![];
    for (index, row) in rows["rows"].as_array().into_iter().flatten().enumerate() {
        retention_requests.push(json!({"requestIndex":index,"cardId":row["cardId"],"desiredRetention":row["targetRetention"]}));
    }
    let targets = rpc(
        backend,
        "FsrsDesiredRetentionForIntervalsBatch",
        json!({"items":retention_requests}),
    )?;
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
    let targets_by_index: HashMap<i64, &Value> = targets["items"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|t| (int(&t["requestIndex"]), t))
        .collect();
    for (index, row) in rows["rows"].as_array().into_iter().flatten().enumerate() {
        // Desktop candidate scoring uses the backend row's ordinary state.
        // Synthetic same-day state is applied only to the displayed card.
        let mut input = query_input(row, None);
        let target = targets_by_index.get(&(index as i64)).copied();
        let intervening = previous
            .get(&input.card_id)
            .map(|i| history_rows.len() - i - 1)
            .unwrap_or(history_rows.len());
        let target_retention = target
            .and_then(|t| t["intervalTargetDesiredRetention"].as_f64())
            .unwrap_or_else(|| row["targetRetention"].as_f64().unwrap_or(0.9));
        input.target_retentions = [Some(target_retention as f32); 4];
        let output = predict(runtime, &input)?;
        scores.push(json!({"cardId":input.card_id.to_string(),"retrievability":output["retrievability"],"interveningReviews":intervening,"targetRetention":target_retention}));
        predictions.insert(input.card_id.to_string(), output);
    }
    rpc(
        backend,
        "SetRwkvReviewQueueScores",
        json!({"deckId":deck,"scores":scores}),
    )?;
    rpc(
        backend,
        "SetRwkvDeckCountScores",
        json!({"deckId":deck,"scores":scores}),
    )?;
    let queue = rpc(backend, "GetQueuedCards", json!({"fetchLimit":1}))?;
    if let Some(current) = queue["cards"].as_array().and_then(|c| c.first()) {
        let cid = &current["card"]["id"];
        if let Some(row) = rows["rows"]
            .as_array()
            .into_iter()
            .flatten()
            .find(|r| &r["cardId"] == cid)
        {
            let latest = previous.get(&int(cid)).map(|i| &history_rows[*i]);
            let mut input = query_input(row, latest);
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
    if let Ok(mut runtimes) = RUNTIMES.lock() {
        runtimes.remove(&handle);
    }
}
