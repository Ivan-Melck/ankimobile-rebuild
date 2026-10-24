//! JSON C boundary around the fork's actual FSRS and RWKV engines.
#![allow(dead_code, unsafe_op_in_unsafe_fn)]
mod compat;
pub mod rwkv;
mod card {
    pub enum CardType {
        New = 0,
        Review = 2,
    }
}
mod scheduler {
    pub mod rwkv {
        pub fn relative_overdueness(r: f32, target: f32) -> f32 {
            r / target.max(0.0001)
        }
    }
}
use fsrs::{FSRS, FSRSItem, FSRSReview};
use rwkv::*;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    cell::RefCell,
    collections::HashMap,
    ffi::{CStr, CString, c_char},
    sync::Arc,
};
type BridgeResult<T> = Result<T, String>;
#[derive(Clone, Deserialize, Serialize)]
struct Event {
    id: i64,
    note: i64,
    deck: i64,
    #[serde(default)]
    preset: Option<i64>,
    time: f64,
    rating: u8,
    seconds: f32,
    state: i64,
    #[serde(default)]
    interval: f32,
    #[serde(default)]
    reps: u32,
    #[serde(default)]
    lapses: u32,
}
#[derive(Deserialize)]
struct Request {
    op: String,
    engine: String,
    #[serde(default)]
    model: String,
    #[serde(default)]
    path: String,
    #[serde(default = "precision_default")]
    precision: String,
    #[serde(default = "retention_default")]
    retention: f32,
    #[serde(default = "max_default")]
    max_interval: u32,
    #[serde(default)]
    parameters: Vec<f32>,
    #[serde(default)]
    history: Vec<Event>,
    #[serde(default)]
    cards: Vec<Event>,
    card: Option<Event>,
    #[serde(default = "days_default")]
    days: u32,
    #[serde(default = "new_default")]
    new_limit: u32,
    #[serde(default = "review_default")]
    review_limit: u32,
    #[serde(default = "yes")]
    include_same_day: bool,
    #[serde(default = "yes")]
    grade_order: bool,
    #[serde(default)]
    time_series: bool,
    #[serde(default)]
    scope_deck: Option<i64>,
}
fn precision_default() -> String {
    "cards_int4_notes_int8".into()
}
fn retention_default() -> f32 {
    0.9
}
fn max_default() -> u32 {
    36500
}
fn days_default() -> u32 {
    30
}
fn new_default() -> u32 {
    20
}
fn review_default() -> u32 {
    200
}
fn yes() -> bool {
    true
}
fn parameters(r: &Request) -> Vec<f32> {
    if !r.parameters.is_empty() {
        r.parameters.clone()
    } else if r.engine == "fsrs6" {
        fsrs::FSRS6_DEFAULT_PARAMETERS.to_vec()
    } else {
        vec![]
    }
}
fn fsrs_model(r: &Request) -> BridgeResult<FSRS> {
    FSRS::new(&parameters(r)).map_err(|e| e.to_string())
}
fn reviews(history: &[Event], id: i64) -> Vec<FSRSReview> {
    let mut prev = None;
    history
        .iter()
        .filter(|e| e.id == id)
        .map(|e| {
            let delta_t = prev
                .map(|t: f64| ((e.time - t) / 86400.0).max(0.0) as f32)
                .unwrap_or(0.0);
            prev = Some(e.time);
            FSRSReview {
                rating: e.rating as u32,
                delta_t,
            }
        })
        .collect()
}
fn memory(r: &Request, f: &FSRS, c: &Event) -> BridgeResult<Option<fsrs::MemoryState>> {
    let revs = reviews(&r.history, c.id);
    if revs.is_empty() {
        if c.reps > 0 && c.interval > 0.0 {
            f.memory_state_from_sm2(2.5, c.interval, 0.9)
                .map(Some)
                .map_err(|e| e.to_string())
        } else {
            Ok(None)
        }
    } else {
        f.memory_state(FSRSItem { reviews: revs }, None)
            .map(Some)
            .map_err(|e| e.to_string())
    }
}
fn elapsed(r: &Request, c: &Event) -> f32 {
    r.history
        .iter()
        .rev()
        .find(|e| e.id == c.id)
        .map(|e| ((c.time - e.time) / 86400.0).max(0.0) as f32)
        .unwrap_or(0.0)
}
fn input(r: &Request, e: &Event, query: bool, previous: Option<&Event>) -> ReviewInput {
    let seconds = previous
        .map(|p| (e.time - p.time).max(0.0) as i64)
        .unwrap_or(0);
    ReviewInput {
        card_id: e.id,
        note_id: Some(e.note),
        deck_id: Some(e.deck),
        preset_id: Some(e.preset.unwrap_or(e.deck)),
        is_query: query,
        ease: if query { None } else { Some(e.rating) },
        duration_millis: if query {
            None
        } else {
            Some((e.seconds * 1000.0) as i64)
        },
        card_type: Some(e.state),
        day_offset: Some((e.time / 86400.0).floor() as i64),
        current_elapsed_days: Some(seconds / 86400),
        current_elapsed_seconds: Some(seconds),
        target_retentions: [Some(r.retention); 4],
        enforce_grade_order: r.grade_order,
    }
}
struct Cached {
    key: String,
    history: String,
    runtime: RwkvRuntime,
}
thread_local! { static CACHE: RefCell<Option<Cached>> = const { RefCell::new(None) }; }
fn with_rwkv<T>(
    r: &Request,
    run: impl FnOnce(&mut RwkvRuntime) -> BridgeResult<T>,
) -> BridgeResult<T> {
    let key = format!(
        "{}:{}:{}:{}:{}",
        r.path, r.model, r.precision, r.retention, r.max_interval
    );
    let history = serde_json::to_string(&r.history).map_err(|e| e.to_string())?;
    CACHE.with(|slot| {
        let mut cache = slot.borrow_mut();
        if cache
            .as_ref()
            .map(|c| c.key != key || c.history != history)
            .unwrap_or(true)
        {
            let mut runtime = RwkvRuntime::load_with_precision(
                r.path.clone().into(),
                r.retention,
                r.max_interval,
                StatePrecision::parse(&r.precision).map_err(|e| e.to_string())?,
                ModelKind::parse(&r.model).map_err(|e| e.to_string())?,
            )
            .map_err(|e| e.to_string())?;
            let mut prior = HashMap::new();
            let inputs = r
                .history
                .iter()
                .map(|e| {
                    let i = input(r, e, false, prior.get(&e.id).copied());
                    prior.insert(e.id, e);
                    i
                })
                .collect();
            runtime
                .warm_up_reviews(inputs, false)
                .map_err(|e| e.to_string())?;
            *cache = Some(Cached {
                key,
                history,
                runtime,
            });
        }
        run(&mut cache.as_mut().unwrap().runtime)
    })
}
fn predict(r: &Request) -> BridgeResult<Value> {
    let c = r.card.as_ref().ok_or("Missing card")?;
    if r.engine.starts_with("rwkv") {
        with_rwkv(r, |runtime| {
            let i = input(r, c, true, r.history.iter().rev().find(|e| e.id == c.id));
            let s = runtime.warm_up_state(&i);
            let out = runtime
                .review(
                    i,
                    ReviewState {
                        card: s.card.as_deref(),
                        note: s.note.as_deref(),
                        deck: s.deck.as_deref(),
                        preset: s.preset.as_deref(),
                        global: s.global.as_deref(),
                    },
                )
                .map_err(|e| e.to_string())?;
            Ok(
                json!({"intervals":out.intervals,"retrievability":out.retrievability,"stability":out.current_s90,"probabilities":out.button_probabilities}),
            )
        })
    } else {
        let f = fsrs_model(r)?;
        let mem = memory(r, &f, c)?;
        let n = f
            .next_states_with_elapsed_days(mem, r.retention, elapsed(r, c))
            .map_err(|e| e.to_string())?;
        Ok(
            json!({"intervals":[n.again.interval,n.hard.interval,n.good.interval,n.easy.interval],
            "retrievability":mem.map(|s|f.current_retrievability(s,elapsed(r,c))),
            "stability":mem.map(|s|s.stability),"difficulty":mem.map(|s|s.difficulty)}),
        )
    }
}
fn training(r: &Request) -> (Vec<FSRSItem>, Vec<i64>) {
    let mut grouped: HashMap<i64, Vec<FSRSReview>> = HashMap::new();
    let mut last = HashMap::new();
    let mut items = vec![];
    let mut ids = vec![];
    for e in &r.history {
        let delta = last
            .get(&e.id)
            .map(|t: &f64| ((e.time - t) / 86400.0).max(0.0) as f32)
            .unwrap_or(0.0);
        last.insert(e.id, e.time);
        let rows = grouped.entry(e.id).or_default();
        rows.push(FSRSReview {
            rating: e.rating as u32,
            delta_t: delta,
        });
        if rows.len() > 1
            && r.scope_deck.is_none_or(|deck| e.deck == deck)
            && (r.include_same_day || delta >= 1.0)
        {
            items.push(FSRSItem {
                reviews: rows.clone(),
            });
            ids.push(e.id);
        }
    }
    (items, ids)
}
fn evaluate(r: &Request) -> BridgeResult<Value> {
    let (items, ids) = training(r);
    if items.len() < 2 {
        return Err("At least two follow-up reviews are needed to evaluate predictions.".into());
    }
    if r.engine.starts_with("rwkv") {
        if r.time_series {
            return Err("Time-series fitting is available for FSRS. RWKV uses causal replay without training on future answers.".into());
        }
        // Resetting just recurrent state leaves the fork's feature clock intact.
        // Calibration needs a fresh feature stream as well as fresh memory state.
        {
            let mut runtime = RwkvRuntime::load_with_precision(
                r.path.clone().into(),
                r.retention,
                r.max_interval,
                StatePrecision::parse(&r.precision).map_err(|e| e.to_string())?,
                ModelKind::parse(&r.model).map_err(|e| e.to_string())?,
            )
            .map_err(|e| e.to_string())?;
            let mut last: HashMap<i64, &Event> = HashMap::new();
            let mut sum = 0.0f32;
            let mut count = 0;
            let mut bins = [(0.0f32, 0.0f32, 0u32); 10];
            for e in &r.history {
                let previous = last.get(&e.id).copied();
                if r.scope_deck.is_none_or(|deck| e.deck == deck)
                    && previous.is_some()
                    && (r.include_same_day || e.time - previous.unwrap().time >= 86400.0)
                {
                    let i = input(r, e, true, previous);
                    let s = runtime.warm_up_state(&i);
                    let out = runtime
                        .review(
                            i,
                            ReviewState {
                                card: s.card.as_deref(),
                                note: s.note.as_deref(),
                                deck: s.deck.as_deref(),
                                preset: s.preset.as_deref(),
                                global: s.global.as_deref(),
                            },
                        )
                        .map_err(|e| e.to_string())?;
                    let p = out.retrievability.clamp(0.0001, 0.9999);
                    let y = if e.rating > 1 { 1.0 } else { 0.0 };
                    sum -= y * p.ln() + (1.0 - y) * (1.0 - p).ln();
                    count += 1;
                    let b = &mut bins[((p * 10.0) as usize).min(9)];
                    b.0 += p;
                    b.1 += y;
                    b.2 += 1;
                }
                let i = input(r, e, false, previous);
                let s = runtime.warm_up_state(&i);
                runtime
                    .review(
                        i,
                        ReviewState {
                            card: s.card.as_deref(),
                            note: s.note.as_deref(),
                            deck: s.deck.as_deref(),
                            preset: s.preset.as_deref(),
                            global: s.global.as_deref(),
                        },
                    )
                    .map_err(|e| e.to_string())?;
                last.insert(e.id, e);
            }
            let mse = bins
                .iter()
                .filter(|b| b.2 > 0)
                .map(|b| (b.0 - b.1).powi(2) / b.2 as f32)
                .sum::<f32>()
                / count as f32;
            Ok(json!({"log_loss":sum/count as f32,"rmse":mse.sqrt(),"samples":count}))
        }
    } else {
        let n = items.len();
        let metrics = if r.time_series {
            fsrs::evaluate_with_time_series_splits(
                fsrs::ComputeParametersInput {
                    train_set: items,
                    card_ids: Some(ids),
                    model_version: if r.engine == "fsrs6" {
                        fsrs::ComputeParametersVersion::Fsrs6
                    } else {
                        fsrs::ComputeParametersVersion::Fsrs7
                    },
                    ..Default::default()
                },
                |_| true,
            )
        } else {
            fsrs_model(r)?.evaluate(items, |_| true)
        }
        .map_err(|e| e.to_string())?;
        Ok(json!({"log_loss":metrics.log_loss,"rmse":metrics.rmse_bins,"samples":n}))
    }
}
fn simulate(r: &Request) -> BridgeResult<Value> {
    if r.cards.is_empty() {
        return Err("Add cards to this deck before simulating.".into());
    }
    if r.engine.starts_with("rwkv") {
        with_rwkv(r, |runtime| {
            let inputs = r
                .cards
                .iter()
                .map(|e| RwkvWorkloadSimulationInput {
                    review_input: input(r, e, true, r.history.iter().rev().find(|h| h.id == e.id)),
                    interval_days: Some(e.interval as i64),
                    ease_factor: Some(2500),
                    reps: Some(e.reps as i64),
                    lapses: Some(e.lapses as i64),
                })
                .collect();
            let o = runtime
                .simulate_workload_from_warm_up(
                    inputs,
                    RwkvWorkloadSimulationConfig {
                        min_dr: 80,
                        max_dr: 95,
                        target_dr_step: 5,
                        days_to_simulate: r.days,
                        review_limit: r.review_limit,
                        new_limit: r.new_limit,
                        new_cards_ignore_review_limit: true,
                        max_interval: r.max_interval,
                        review_order: compat::ReviewCardOrder::RetrievabilityAscending,
                        suspend_after_lapses: None,
                        state_update_interval: 1,
                        review_model: RwkvWorkloadReviewModel {
                            grade_seconds: [20.0, 15.0, 12.0, 8.0],
                            bucket_probabilities: vec![],
                        },
                    },
                    &mut |_, _| Ok(()),
                )
                .map_err(|e| e.to_string())?;
            Ok(
                json!({"points":o.points.into_iter().map(|(ret,p)|json!({"retention":ret as f32/100.0,"reviews":p.review_count,"seconds":p.cost,"memorized":p.memorized})).collect::<Vec<_>>()}),
            )
        })
    } else {
        let f = fsrs_model(r)?;
        let p = fsrs::check_and_fill_parameters(&parameters(r)).map_err(|e| e.to_string())?;
        let mut points = vec![];
        for ret in [0.8, 0.85, 0.9, 0.95] {
            let mut cards = vec![];
            for c in &r.cards {
                if let Some(m) = memory(r, &f, c)? {
                    cards.push(fsrs::Card {
                        id: c.id,
                        stability: m.stability,
                        difficulty: m.difficulty,
                        last_date: -elapsed(r, c),
                        due: c.interval - elapsed(r, c),
                        interval: c.interval,
                        reps: c.reps,
                        lapses: c.lapses,
                        desired_retention: ret,
                        parameters: Arc::new(p.clone()),
                    });
                }
            }
            let cfg = fsrs::SimulatorConfig {
                deck_size: r.cards.len(),
                learn_span: r.days as usize,
                max_cost_perday: f32::INFINITY,
                max_ivl: r.max_interval as f32,
                learn_limit: r.new_limit as usize,
                review_limit: r.review_limit as usize,
                ..Default::default()
            };
            let o = fsrs::simulate_summary(&cfg, &p, ret, Some(42), Some(cards))
                .map_err(|e| e.to_string())?;
            points.push(json!({"retention":ret,"reviews":o.review_count+o.learn_count,"seconds":o.cost,"memorized":o.memorized}));
        }
        Ok(json!({"points":points}))
    }
}
fn dispatch(r: Request) -> BridgeResult<Value> {
    if !(0.7..=0.99).contains(&r.retention)
        || !(1..=36500).contains(&r.max_interval)
        || !(1..=365).contains(&r.days)
    {
        return Err("Invalid scheduling bounds".into());
    }
    if r.history
        .iter()
        .any(|e| !(1..=4).contains(&e.rating) || !e.time.is_finite() || !e.seconds.is_finite())
    {
        return Err("Invalid review history".into());
    }
    match r.op.as_str() {
        "predict" => predict(&r),
        "simulate" => simulate(&r),
        "evaluate" => evaluate(&r),
        "optimize" => {
            let (items, ids) = training(&r);
            if items.len() < 100 {
                return Err("Optimization needs at least 100 follow-up reviews. Keep studying with the model defaults for now.".into());
            }
            let p = fsrs::compute_parameters(fsrs::ComputeParametersInput {
                train_set: items,
                card_ids: Some(ids),
                enable_short_term: r.include_same_day,
                model_version: if r.engine == "fsrs6" {
                    fsrs::ComputeParametersVersion::Fsrs6
                } else {
                    fsrs::ComputeParametersVersion::Fsrs7
                },
                ..Default::default()
            })
            .map_err(|e| e.to_string())?;
            Ok(json!({"parameters":p}))
        }
        _ => Err("Unknown engine operation".into()),
    }
}
pub fn request_json(s: &str) -> String {
    let result = std::panic::catch_unwind(|| {
        serde_json::from_str::<Request>(s)
            .map_err(|e| e.to_string())
            .and_then(dispatch)
    });
    match result {
        Ok(Ok(v)) => v.to_string(),
        Ok(Err(e)) => json!({"error":e}).to_string(),
        Err(_) => {
            json!({"error":"The scheduling engine could not complete this request."}).to_string()
        }
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn scheduling_engine_request(request: *const c_char) -> *mut c_char {
    if request.is_null() {
        return CString::new("{\"error\":\"Missing request\"}")
            .unwrap()
            .into_raw();
    }
    let s = unsafe { CStr::from_ptr(request) }.to_string_lossy();
    CString::new(request_json(&s)).unwrap().into_raw()
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn scheduling_engine_free(result: *mut c_char) {
    if !result.is_null() {
        drop(unsafe { CString::from_raw(result) })
    }
}
