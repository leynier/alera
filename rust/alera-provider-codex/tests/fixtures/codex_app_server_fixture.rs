use serde_json::{json, Value};
use std::io::{self, BufRead, Write};

fn main() {
    let stdin = io::stdin();
    let mut stdout = io::BufWriter::new(io::stdout());
    for line in stdin.lock().lines() {
        let Ok(line) = line else { break };
        let Ok(message) = serde_json::from_str::<Value>(&line) else {
            continue;
        };
        let Some(method) = message.get("method").and_then(Value::as_str) else {
            continue;
        };
        let Some(id) = message.get("id") else {
            continue;
        };
        let result = match method {
            "initialize" => json!({
                "codexHome": "/tmp/codex",
                "platformFamily": "unix",
                "platformOs": "linux",
                "userAgent": "fixture",
            }),
            "thread/start" => json!({
                "thread": { "id": "native-thread-fixture" },
            }),
            "thread/resume" => json!({
                "thread": { "id": message["params"]["threadId"] },
            }),
            "turn/start" => json!({
                "turn": { "id": "native-turn-fixture" },
            }),
            "turn/interrupt" => json!({}),
            _ => json!({}),
        };
        if method == "initialize" {
            let originator =
                std::env::var("CODEX_INTERNAL_ORIGINATOR_OVERRIDE").unwrap_or_default();
            let notice = json!({
                "method": "test/originator",
                "params": { "originator": originator },
            });
            serde_json::to_writer(&mut stdout, &notice).expect("write fixture notification");
            stdout
                .write_all(b"\n")
                .expect("write fixture notification newline");
        }
        let response = json!({ "id": id, "result": result });
        serde_json::to_writer(&mut stdout, &response).expect("write fixture response");
        stdout.write_all(b"\n").expect("write fixture newline");
        stdout.flush().expect("flush fixture response");
    }
}
