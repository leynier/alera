use std::path::PathBuf;

use serde_json::{json, Value};

use super::{input_schema, payload_schema, EVENT_KINDS};

/// The `events/list` entries the edge serves.
pub fn edge_catalog() -> Value {
    let events: Vec<Value> = EVENT_KINDS
        .iter()
        .map(|kind| {
            json!({
                "name": kind.name,
                "description": kind.description,
                "delivery": ["webhook"],
                "inputSchema": input_schema(kind),
                "payloadSchema": payload_schema(kind),
            })
        })
        .collect();
    json!({"version": 1, "events": events})
}

/// The edge serves a copy of the event catalog. Set `ALERA_UPDATE_EVENT_CATALOG=1` to
/// rewrite it after changing an event.
#[test]
fn event_catalog_matches_edge_copy() {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../edge/src/mcp/event_catalog.json");
    let expected = edge_catalog();
    if std::env::var_os("ALERA_UPDATE_EVENT_CATALOG").is_some() {
        let text = serde_json::to_string_pretty(&expected).unwrap_or_default() + "\n";
        if let Err(error) = std::fs::write(&path, text) {
            panic!("write {}: {error}", path.display());
        }
        return;
    }
    let actual: Value = serde_json::from_str(&std::fs::read_to_string(&path).unwrap_or_default())
        .unwrap_or_default();
    assert_eq!(
        actual, expected,
        "edge/src/mcp/event_catalog.json is stale; run with ALERA_UPDATE_EVENT_CATALOG=1"
    );
}
