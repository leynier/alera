use std::io::{self, BufRead, Write};

fn main() {
    let stdin = io::stdin();
    let mut stdout = io::BufWriter::new(io::stdout());
    let mut prompt_id: Option<serde_json::Value> = None;
    for line in stdin.lock().lines() {
        let Ok(line) = line else { return };
        let Ok(frame) = serde_json::from_str::<serde_json::Value>(&line) else {
            return;
        };
        if frame.get("method").is_none() && frame.get("id").is_some() {
            if let Some(id) = prompt_id.take() {
                respond(
                    &mut stdout,
                    Some(id),
                    serde_json::json!({"stopReason":"end_turn"}),
                );
                notify_state(&mut stdout);
            }
            continue;
        }
        let Some(method) = frame.get("method").and_then(serde_json::Value::as_str) else {
            continue;
        };
        let id = frame.get("id").cloned();
        match method {
            "initialize" => respond(
                &mut stdout,
                id,
                serde_json::json!({
                    "protocolVersion": 2,
                    "agentCapabilities": {"sessionCapabilities": {"resume": {}}},
                    "authMethods": []
                }),
            ),
            "session/new" => respond(
                &mut stdout,
                id,
                serde_json::json!({"sessionId":"fixture-session"}),
            ),
            "session/resume" => respond(
                &mut stdout,
                id,
                serde_json::json!({"sessionId":"fixture-session"}),
            ),
            "session/load" => respond(
                &mut stdout,
                id,
                serde_json::json!({"sessionId":"fixture-session"}),
            ),
            "session/prompt" => {
                prompt_id = id;
                notify(
                    &mut stdout,
                    serde_json::json!({
                        "sessionId":"fixture-session",
                        "title":"Run command",
                        "subject":{"type":"command","command":"echo fixture","cwd":"/tmp"},
                        "options":[{"optionId":"allow-once","kind":"allow_once","name":"Allow once"}]
                    }),
                    77,
                    "session/request_permission",
                );
            }
            "session/cancel" => notify_state(&mut stdout),
            "session/set_config_option" => respond(&mut stdout, id, serde_json::json!({})),
            _ if id.is_some() => respond(&mut stdout, id, serde_json::json!({})),
            _ => {}
        }
    }
}

fn respond(output: &mut impl Write, id: Option<serde_json::Value>, result: serde_json::Value) {
    let Some(id) = id else { return };
    let frame = serde_json::json!({"jsonrpc":"2.0","id":id,"result":result});
    writeln!(output, "{frame}").unwrap();
    output.flush().unwrap();
}

fn notify(output: &mut impl Write, params: serde_json::Value, id: i64, method: &str) {
    let frame = serde_json::json!({"jsonrpc":"2.0","id":id,"method":method,"params":params});
    writeln!(output, "{frame}").unwrap();
    output.flush().unwrap();
}

fn notify_state(output: &mut impl Write) {
    let frame = serde_json::json!({
        "jsonrpc":"2.0",
        "method":"session/update",
        "params":{"sessionId":"fixture-session","update":{"sessionUpdate":"state_update","state":"idle","stopReason":"cancelled"}}
    });
    writeln!(output, "{frame}").unwrap();
    output.flush().unwrap();
}
