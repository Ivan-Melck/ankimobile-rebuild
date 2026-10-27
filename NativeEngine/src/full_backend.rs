//! Stable JSON/Protobuf bridge to every service in the pinned Anki backend.
//! Integer IDs use protobuf JSON's decimal strings, retaining all 64 bits.
use anki::backend::{Backend, init_backend};
use prost::Message;
use prost_reflect::{DescriptorPool, DynamicMessage};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    ffi::{CStr, CString, c_char},
    sync::{
        LazyLock, Mutex,
        atomic::{AtomicU64, Ordering},
    },
};
static DESCRIPTORS: LazyLock<DescriptorPool> = LazyLock::new(|| {
    DescriptorPool::decode(&include_bytes!(concat!(env!("OUT_DIR"), "/anki-descriptors.bin"))[..])
        .unwrap()
});
static SERVICES: LazyLock<Vec<anki_proto_gen::BackendService>> =
    LazyLock::new(|| anki_proto_gen::get_services(&DESCRIPTORS).1);
static BACKENDS: LazyLock<Mutex<HashMap<u64, Backend>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
static NEXT_HANDLE: AtomicU64 = AtomicU64::new(1);
#[derive(Deserialize)]
struct Call {
    op: String,
    #[serde(default)]
    handle: u64,
    service: Option<String>,
    method: Option<String>,
    #[serde(default)]
    input: Value,
}
fn execute(call: Call) -> Result<Value, String> {
    match call.op.as_str() {
        "create" => {
            let init = anki_proto::backend::BackendInit {
                preferred_langs: vec!["en".into()],
                ..Default::default()
            };
            let backend = init_backend(&init.encode_to_vec())?;
            let handle = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed);
            BACKENDS
                .lock()
                .map_err(|_| "Backend registry unavailable")?
                .insert(handle, backend);
            Ok(json!({"handle":handle}))
        }
        "destroy" => {
            super::collection_rwkv::release(call.handle);
            BACKENDS
                .lock()
                .map_err(|_| "Backend registry unavailable")?
                .remove(&call.handle);
            Ok(json!({}))
        }
        "schema" => {
            let name = call.input["name"].as_str().ok_or("Missing message name")?;
            let descriptor = DESCRIPTORS
                .get_message_by_name(name)
                .ok_or("Unknown message type")?;
            Ok(json!({"fields":descriptor.fields().map(|f| {
                let kind=f.kind();
                let (name,values)=match kind {
                    prost_reflect::Kind::Bool => ("bool",vec![]),
                    prost_reflect::Kind::String => ("string",vec![]),
                    prost_reflect::Kind::Bytes => ("bytes",vec![]),
                    prost_reflect::Kind::Message(_) => ("message",vec![]),
                    prost_reflect::Kind::Enum(ref e) => ("enum",e.values().map(|v|v.name().to_string()).collect()),
                    _ => ("number",vec![])
                };
                json!({"name":f.json_name(),"kind":name,"repeated":f.is_list(),"values":values})
            }).collect::<Vec<_>>()}))
        }
        "catalog" => {
            let services = &*SERVICES;
            Ok(
                json!({"revision":"96af4ca9d214e71743b1186fd2ceab1a7e7e3f32", "services":services.iter().map(|s|json!({"name":s.name,"methods":s.all_methods().map(|m|json!({"name":m.proto.name(),"input":m.proto.input().full_name(),"output":m.proto.output().full_name()})).collect::<Vec<_>>()})).collect::<Vec<_>>()}),
            )
        }
        "call" => {
            // Clone the handle, then release the registry lock. Abort/Progress must be
            // able to run concurrently with a long sync/import on this backend.
            let backend = BACKENDS
                .lock()
                .map_err(|_| "Backend registry unavailable")?
                .get(&call.handle)
                .cloned()
                .ok_or("Backend handle is closed")?;
            let name = call.service.as_deref().ok_or("Missing service")?;
            let method_name = call.method.as_deref().ok_or("Missing method")?;
            let result = call_backend(&backend, name, method_name, call.input.clone())?;
            if name == "BackendSchedulerService" && method_name == "AnswerCard" {
                super::collection_rwkv::record_answer(call.handle, &backend, &call.input);
            }
            if name == "BackendCollectionService" && ["Undo", "Redo"].contains(&method_name) {
                super::collection_rwkv::reconcile_undo(call.handle, &result, method_name == "Redo");
            }
            let changes = result
                .get("changes")
                .filter(|v| v.is_object())
                .unwrap_or(&result);
            if !["AnswerCard", "Undo", "Redo", "SetCurrentDeck"].contains(&method_name)
                && [
                    "card",
                    "note",
                    "deck",
                    "notetype",
                    "config",
                    "deckConfig",
                    "studyQueues",
                ]
                .iter()
                .any(|field| changes[*field].as_bool() == Some(true))
            {
                super::collection_rwkv::invalidate_candidates(call.handle);
            }
            if name == "BackendCollectionService"
                && ["OpenCollection", "CloseCollection"].contains(&method_name)
            {
                super::collection_rwkv::release(call.handle);
            }
            if name == "BackendSyncService"
                && (method_name == "FullUploadOrDownload"
                    || (method_name == "SyncCollection"
                        && result["remoteCollectionChanged"] == true))
            {
                // Sync does not return OpChanges. Incoming history/objects or
                // a replaced collection invalidate all reviewer-local state.
                super::collection_rwkv::release(call.handle);
            }
            Ok(result)
        }
        #[cfg(feature = "validation-comparison")]
        "comparison_inspect" => {
            let backend = BACKENDS
                .lock()
                .map_err(|_| "Backend registry unavailable")?
                .get(&call.handle)
                .cloned()
                .ok_or("Backend handle is closed")?;
            let mut tables = serde_json::Map::new();
            for table in ["cards", "notes", "revlog", "graves"] {
                let order = if table == "graves" { "oid,type" } else { "id" };
                let request = json!({"kind":"query", "sql": format!("select * from {table} order by {order}"), "args": [], "first_row_only": false});
                let bytes = backend
                    .run_db_command_bytes(&serde_json::to_vec(&request).unwrap())
                    .map_err(|_| format!("Unable to inspect comparison table {table}"))?;
                tables.insert(
                    table.into(),
                    serde_json::from_slice::<Value>(&bytes).map_err(|e| e.to_string())?,
                );
            }
            Ok(
                json!({"tables": tables, "recurrent": super::collection_rwkv::comparison_snapshot(call.handle)}),
            )
        }
        "rwkv_prepare" => {
            let backend = BACKENDS
                .lock()
                .map_err(|_| "Backend registry unavailable")?
                .get(&call.handle)
                .cloned()
                .ok_or("Backend handle is closed")?;
            super::collection_rwkv::prepare(call.handle, &backend, call.input)
        }

        _ => Err("Unknown backend operation".into()),
    }
}
pub fn request_json(input: &str) -> String {
    match std::panic::catch_unwind(|| {
        serde_json::from_str::<Call>(input)
            .map_err(|e| e.to_string())
            .and_then(execute)
    }) {
        Ok(Ok(value)) => json!({"result":value}).to_string(),
        Ok(Err(error)) => json!({"error":error}).to_string(),
        Err(_) => {
            json!({"error":"The Anki backend could not complete this operation."}).to_string()
        }
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn anki_backend_request(input: *const c_char) -> *mut c_char {
    let response = if input.is_null() {
        json!({"error":"Missing request"}).to_string()
    } else {
        request_json(&unsafe { CStr::from_ptr(input) }.to_string_lossy())
    };
    CString::new(response).unwrap().into_raw()
}

pub(crate) fn call_backend(
    backend: &Backend,
    name: &str,
    method_name: &str,
    input: Value,
) -> Result<Value, String> {
    let service = SERVICES
        .iter()
        .find(|s| s.name == name)
        .ok_or("Unknown backend service")?;
    let method = service
        .all_methods()
        .find(|m| m.proto.name() == method_name)
        .ok_or("Unknown backend method")?;
    let input = if input.is_null() { json!({}) } else { input };
    let message =
        DynamicMessage::deserialize(method.proto.input(), input).map_err(|e| e.to_string())?;
    let bytes = backend
        .run_service_method(
            service.index as u32,
            method.index as u32,
            &message.encode_to_vec(),
        )
        .map_err(|bytes| {
            anki_proto::backend::BackendError::decode(bytes.as_slice())
                .map(|e| format!("{} [backend:{}]", e.message, e.kind))
                .unwrap_or_else(|e| e.to_string())
        })?;
    let message = DynamicMessage::decode(method.proto.output(), bytes.as_slice())
        .map_err(|e| e.to_string())?;
    serde_json::to_value(message).map_err(|e| e.to_string())
}
