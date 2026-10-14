use serde_json::{json, Value};
use std::io::{self, BufRead, Write};

fn send(value: Value) {
    let mut stdout = io::stdout().lock();
    writeln!(stdout, "{}", value).expect("fixture stdout");
    stdout.flush().expect("fixture flush");
}

fn main() {
    let stdin = io::stdin();
    for line in stdin.lock().lines() {
        let Ok(line) = line else {
            break;
        };
        let Ok(frame) = serde_json::from_str::<Value>(&line) else {
            continue;
        };
        let id = frame.get("id").cloned();
        let Some(method) = frame.get("method").and_then(Value::as_str) else {
            continue;
        };
        match method {
            "initialize" => {
                if let Some(id) = id {
                    send(json!({"jsonrpc":"2.0","id":id,"result":{
                        "experimentalApi":false,"grantedCapabilities":[],"museHome":"/tmp/muse",
                        "platformFamily":"unix","platformOs":"linux","sessionDurability":"durable",
                        "userAgent":"fixture","schema":{"version":1,"fingerprint":"sha256:test"},
                        "serverInfo":{"name":"fixture","version":"1"}
                    }}));
                }
            }
            "initialized" => {}
            "session/start" | "session/resume" => {
                let params = frame.get("params").cloned().unwrap_or_default();
                let session_id = params
                    .get("sessionId")
                    .and_then(Value::as_str)
                    .unwrap_or("fixture-session");
                if let Some(id) = id {
                    send(json!({"jsonrpc":"2.0","id":id,"result":{"session":{
                        "sessionId":session_id,"status":"idle","activeTurnId":null,"turnCount":0,
                        "path":"","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z",
                        "workspaceRoot":"/tmp","providerId":"muse","modelId":"muse-large-2"
                    },"viewCursor":"v:fixture:1"}}));
                }
            }
            "turn/start" => {
                let params = frame.get("params").cloned().unwrap_or_default();
                let command_id = params.get("commandId").cloned().unwrap_or(Value::Null);
                if let Some(id) = id {
                    send(
                        json!({"jsonrpc":"2.0","id":id,"result":{"commandId":command_id,
                        "status":"accepted","turnId":"fixture-turn","startedNewTurn":true,"disposition":"started"}}),
                    );
                }
                send(json!({"jsonrpc":"2.0","method":"turn/started","params":{
                    "sessionId":"fixture-session","turnId":"fixture-turn","commandId":command_id,"viewCursor":"v:fixture:2"}}));
            }
            "turn/cancel" | "turn/interrupt" => {
                if let Some(id) = id {
                    send(json!({"jsonrpc":"2.0","id":id,"result":{"status":"accepted"}}));
                }
                send(json!({"jsonrpc":"2.0","method":"turn/completed","params":{
                    "sessionId":"fixture-session","turnId":"fixture-turn","terminal":"cancelled","reason":"cancelled"}}));
            }
            "approval/decide" | "userInput/answer" => {
                if let Some(id) = id {
                    send(json!({"jsonrpc":"2.0","id":id,"result":{"status":"accepted"}}));
                }
            }
            _ => {
                if let Some(id) = id {
                    send(json!({"jsonrpc":"2.0","id":id,"result":{}}));
                }
            }
        }
    }
}
