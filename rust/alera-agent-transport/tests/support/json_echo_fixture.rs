use std::io::{BufRead, Read, Write};
use std::path::Path;
use std::time::Duration;

use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

#[tokio::main]
async fn main() {
    let args = std::env::args_os().skip(1).collect::<Vec<_>>();
    if args
        .first()
        .is_some_and(|arg| arg == "--partial-write-gate")
    {
        gated_input(Path::new(&args[1]), Path::new(&args[2]));
        return;
    }
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
            Some("burst") | Some("burst-before-read") => {
                let payload = (0..100)
                    .flat_map(|n| format!("{{\"n\":{n}}}\n").into_bytes())
                    .collect::<Vec<_>>();
                stdout.write_all(&payload).await.unwrap();
                stdout.flush().await.unwrap();
                if request["op"] == "burst-before-read" {
                    let Some(line) = lines.next_line().await.unwrap() else {
                        return;
                    };
                    let request = serde_json::from_str::<Value>(&line).unwrap();
                    let received_bytes = request["value"].as_str().unwrap().len();
                    write_json(&mut stdout, json!({"received_bytes": received_bytes}), true).await;
                }
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

fn gated_input(prefix_received: &Path, resume: &Path) {
    let stdin = std::io::stdin();
    let mut stdin = stdin.lock();
    let mut prefix = [0_u8; 1];
    stdin.read_exact(&mut prefix).unwrap();
    std::fs::write(prefix_received, b"prefix received").unwrap();
    while !resume.exists() {
        std::thread::sleep(Duration::from_millis(2));
    }

    let input = std::io::Cursor::new(prefix).chain(stdin);
    let mut stdout = std::io::stdout().lock();
    let mut count = 0;
    let mut received = Vec::new();
    for line in std::io::BufReader::new(input).lines() {
        let request = match serde_json::from_str::<Value>(&line.unwrap()) {
            Ok(request) => request,
            Err(error) => {
                writeln!(stdout, "{}", json!({"invalid_frame": error.to_string()})).unwrap();
                stdout.flush().unwrap();
                return;
            }
        };
        if request["op"] == "exit" {
            writeln!(stdout, "{}", json!({"finished": count})).unwrap();
            stdout.flush().unwrap();
            return;
        }
        count += 1;
        let summary = json!({
            "id": request["id"],
            "received_bytes": request["value"].as_str().map_or(0, str::len)
        });
        writeln!(stdout, "{summary}").unwrap();
        received.push(summary);
        stdout.flush().unwrap();
    }
    std::fs::write(
        resume.parent().unwrap().join("completed"),
        serde_json::to_vec(&received).unwrap(),
    )
    .unwrap();
    while resume.parent().unwrap().join("hold-after-eof").exists() {
        std::thread::sleep(Duration::from_millis(2));
    }
    std::fs::write(resume.parent().unwrap().join("exit-ready"), b"exit ready").unwrap();
    writeln!(stdout, "{}", json!({"eof_frames": count})).unwrap();
    stdout.flush().unwrap();
}

async fn write_json(stdout: &mut tokio::io::Stdout, value: Value, newline: bool) {
    let payload = serde_json::to_vec(&value).unwrap();
    stdout.write_all(&payload).await.unwrap();
    if newline {
        stdout.write_all(b"\n").await.unwrap();
    }
    stdout.flush().await.unwrap();
}
