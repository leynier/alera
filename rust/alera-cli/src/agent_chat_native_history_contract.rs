//! Exact bodies for native history controls in the public MCP groups.

use serde_json::{json, Value};

pub(crate) fn schema(operation: &str) -> Option<Value> {
    let id = || json!({"type":"string", "minLength":1});
    let (fields, required): (_, &[&str]) = match operation {
        "rewind" => (
            vec![
                ("turnId", id()),
                (
                    "mode",
                    json!({"type":"string","enum":["transcript","native"],"default":"transcript"}),
                ),
            ],
            &["chatId", "turnId"],
        ),
        "rewind-files" => (vec![("turnId", id())], &["chatId", "turnId"]),
        "file-checkpoints-configure" => (
            vec![("enabled", json!({"type":"boolean"}))],
            &["chatId", "enabled"],
        ),
        "native-history-operation" => (vec![("operationId", id())], &["chatId"]),
        "native-history-reconcile" => (
            vec![
                ("operationId", id()),
                (
                    "expectedRevision",
                    json!({"type":"integer","minimum":0,"maximum":i64::MAX}),
                ),
                (
                    "action",
                    json!({"type":"string","enum":["finishAcknowledged","restartFromTranscript","cancelUnstarted","continueFromCurrentFiles"]}),
                ),
            ],
            &["chatId", "operationId", "action"],
        ),
        _ => return None,
    };
    let mut properties = serde_json::Map::new();
    for key in ["chatId", "workspaceId", "hostId"] {
        properties.insert(key.into(), id());
    }
    for (key, value) in fields {
        properties.insert(key.into(), value);
    }
    Some(
        json!({"type":"object","properties":properties,"required":required,"additionalProperties":false}),
    )
}
