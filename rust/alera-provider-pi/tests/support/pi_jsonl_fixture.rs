use serde_json::{json, Value};
use std::io::{self, BufRead, Write};

fn write_record(record: Value) {
    let mut stdout = io::stdout().lock();
    serde_json::to_writer(&mut stdout, &record).expect("write fixture record");
    stdout.write_all(b"\n").expect("write fixture newline");
    stdout.flush().expect("flush fixture record");
}

fn state() -> Value {
    json!({
        "sessionFile": "/tmp/pi-fixture/session.jsonl",
        "sessionId": "fixture-session",
        "model": { "provider": "fixture", "id": "model" },
        "isStreaming": false,
        "isCompacting": false,
        "pendingMessageCount": 0
    })
}

fn main() {
    let args: Vec<_> = std::env::args_os().collect();
    let extension_index = args
        .iter()
        .position(|arg| arg == "--extension")
        .expect("default permission extension must be injected");
    let extension = std::path::Path::new(&args[extension_index + 1]);
    assert!(
        extension.exists(),
        "extension lease must outlive the process"
    );
    let permission = extension.parent().unwrap().join("permission_extension.mjs");
    assert!(std::fs::read_to_string(permission)
        .unwrap()
        .contains("tool_call"));
    for line in io::stdin().lock().lines() {
        let Ok(line) = line else { break };
        let Ok(record) = serde_json::from_str::<Value>(&line) else {
            continue;
        };
        let Some(command) = record.get("type").and_then(Value::as_str) else {
            continue;
        };
        let id = record.get("id").cloned();
        match command {
            "get_state" => write_record(json!({
                "type": "response",
                "id": id,
                "command": command,
                "success": true,
                "data": state()
            })),
            "new_session" | "switch_session" | "set_model" | "abort" => write_record(json!({
                "type": "response",
                "id": id,
                "command": command,
                "success": true,
                "data": { "cancelled": false }
            })),
            "prompt" => {
                write_record(json!({
                    "type": "response",
                    "command": "prompt",
                    "success": true
                }));
                write_record(json!({ "type": "agent_start" }));
                write_record(json!({
                    "type": "message_update",
                    "assistantMessageEvent": { "type": "text_delta", "delta": "fixture" }
                }));
                write_record(json!({ "type": "agent_settled" }));
            }
            "extension_ui_response" => {}
            _ => write_record(json!({
                "type": "response",
                "id": id,
                "command": command,
                "success": false,
                "error": "unknown fixture command"
            })),
        }
    }
}
