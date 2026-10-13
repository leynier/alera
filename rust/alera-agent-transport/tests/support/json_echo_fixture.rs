use std::io::Write;
use std::time::Duration;

use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

#[tokio::main]
async fn main() {
    let stdin = tokio::io::stdin();
    let mut lines = BufReader::new(stdin).lines();
    let mut stdout = tokio::io::stdout();

    while let Ok(Some(line)) = lines.next_line().await {
        let Ok(request) = serde_json::from_str::<Value>(&line) else {
            continue;
        };
        match request.get("op").and_then(Value::as_str) {
            Some("echo") => write_json(&mut stdout, json!({"echo": request["value"]}), true).await,
            Some("fragmented") => {
                let payload = serde_json::to_vec(&json!({"fragmented": request["value"]})).unwrap();
                for chunk in payload.chunks(2) {
                    stdout.write_all(chunk).await.unwrap();
                    stdout.flush().await.unwrap();
                    tokio::task::yield_now().await;
                }
                stdout.write_all(b"\n").await.unwrap();
                stdout.flush().await.unwrap();
            }
            Some("multi") => {
                let first = serde_json::to_vec(&json!({"n": 1})).unwrap();
                let second = serde_json::to_vec(&json!({"n": 2})).unwrap();
                stdout.write_all(&first).await.unwrap();
                stdout.write_all(b"\n").await.unwrap();
                stdout.write_all(&second).await.unwrap();
                stdout.write_all(b"\n").await.unwrap();
                stdout.flush().await.unwrap();
            }
            Some("no-final-newline") => {
                let payload = serde_json::to_vec(&json!({"done": true})).unwrap();
                stdout.write_all(&payload).await.unwrap();
                stdout.flush().await.unwrap();
                return;
            }
            Some("invalid") => {
                stdout.write_all(b"{invalid json}\n").await.unwrap();
                stdout.flush().await.unwrap();
            }
            Some("invalid-utf8") => {
                stdout.write_all(&[0xff, b'\n']).await.unwrap();
                stdout.flush().await.unwrap();
            }
            Some("oversized") => {
                let payload = json!({"payload": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"});
                write_json(&mut stdout, payload, true).await;
            }
            Some("f") | Some("oversized-no-final-newline") => {
                let payload = json!({"payload": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"});
                let bytes = serde_json::to_vec(&payload).unwrap();
                stdout.write_all(&bytes).await.unwrap();
                stdout.flush().await.unwrap();
                return;
            }
            Some("b") | Some("buffered-oversized") => {
                let mut payload = serde_json::to_vec(&json!({"ok": true})).unwrap();
                payload.push(b'\n');
                payload.extend_from_slice(
                    &serde_json::to_vec(&json!({
                        "payload": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
                    }))
                    .unwrap(),
                );
                payload.push(b'\n');
                stdout.write_all(&payload).await.unwrap();
                stdout.flush().await.unwrap();
            }
            Some("stderr-flood") => {
                let mut stderr = std::io::stderr();
                let block = vec![b'e'; 8192];
                for _ in 0..32 {
                    stderr.write_all(&block).unwrap();
                }
                stderr.flush().unwrap();
                write_json(&mut stdout, json!({"stderr": "drained"}), true).await;
            }
            Some("write-before-read") => {
                let preface = "x".repeat(128 * 1024);
                write_json(&mut stdout, json!({"preface": preface}), true).await;
                let Some(line) = lines.next_line().await.unwrap() else {
                    return;
                };
                let Ok(request) = serde_json::from_str::<Value>(&line) else {
                    return;
                };
                let received_bytes = request
                    .get("value")
                    .and_then(Value::as_str)
                    .map_or(0, str::len);
                write_json(&mut stdout, json!({"received_bytes": received_bytes}), true).await;
            }
            Some("sleep") => {
                tokio::time::sleep(Duration::from_secs(60)).await;
            }
            Some("exit") => return,
            Some("exit-nonzero") => std::process::exit(7),
            _ => write_json(&mut stdout, json!({"unknown": true}), true).await,
        }
    }
}

async fn write_json(stdout: &mut tokio::io::Stdout, value: Value, newline: bool) {
    let payload = serde_json::to_vec(&value).unwrap();
    stdout.write_all(&payload).await.unwrap();
    if newline {
        stdout.write_all(b"\n").await.unwrap();
    }
    stdout.flush().await.unwrap();
}
