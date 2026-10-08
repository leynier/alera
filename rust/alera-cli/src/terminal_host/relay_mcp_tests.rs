use std::path::PathBuf;

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use ed25519_dalek::{Signer, SigningKey};
use serde_json::{json, Value};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;

use super::*;

const ISSUER: &str = "https://fixture.test";

fn encode(bytes: impl AsRef<[u8]>) -> String {
    URL_SAFE_NO_PAD.encode(bytes)
}

fn call_grant(key: &SigningKey, overrides: Value) -> String {
    let now = chrono::Utc::now().timestamp();
    let mut claims = json!({
        "iss": ISSUER, "aud": "alera-runtime-mcp", "sub": "account",
        "iat": now, "nbf": now, "exp": now + 120, "jti": "call-1",
        "accountId": "account", "runtimeId": "runtime", "grantId": "grant",
        "clientId": "client", "clientName": "Fixture", "tool": "runtime_status", "access": "read",
    });
    for (key, value) in overrides.as_object().cloned().unwrap_or_default() {
        claims[key] = value;
    }
    let header = encode(
        serde_json::to_vec(&json!({ "alg": "EdDSA", "typ": "mcp-call+jwt", "kid": "k" })).unwrap(),
    );
    let input = format!("{header}.{}", encode(serde_json::to_vec(&claims).unwrap()));
    format!("{input}.{}", encode(key.sign(input.as_bytes()).to_bytes()))
}

async fn jwks_origin(key: &SigningKey) -> (GrantVerifier, tokio::task::JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let body = json!({ "keys": [{
        "kty": "OKP", "crv": "Ed25519", "alg": "EdDSA", "kid": "k",
        "x": encode(key.verifying_key().to_bytes()),
    }]})
    .to_string();
    let server = tokio::spawn(async move {
        loop {
            let (mut socket, _) = listener.accept().await.unwrap();
            let mut buffer = [0; 4096];
            let _ = socket.read(&mut buffer).await;
            let _ = socket
                .write_all(
                    format!(
                        "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                        body.len()
                    )
                    .as_bytes(),
                )
                .await;
        }
    });
    let verifier =
        GrantVerifier::with_url(ISSUER.into(), format!("http://{address}/jwks")).unwrap();
    (verifier, server)
}

/// `echo` stands in for the `alera` binary: the tool output is its argv.
fn owned_link(access: McpAccess, verifier: GrantVerifier) -> (McpLink, McpLinkLifetime) {
    McpLink::new(
        access,
        ToolExecution {
            executable: PathBuf::from("echo"),
            runtime_dir: PathBuf::from("/tmp/runtime"),
        },
        verifier,
    )
}

fn link(access: McpAccess, verifier: GrantVerifier) -> McpLink {
    let (link, lifetime) = owned_link(access, verifier);
    std::mem::forget(lifetime);
    link
}

async fn call(link: &McpLink, id: &str, grant: String, tool: &str) -> Value {
    let (control, mut frames) = mpsc::channel(4);
    let payload = serde_json::to_vec(&json!({
        "type": "mcp.call", "id": id, "grant": grant, "tool": tool, "arguments": {},
    }))
    .unwrap();
    link.handle_frame(
        &payload,
        CallContext {
            account_id: "account",
            runtime_id: "runtime",
            control: &control,
        },
    );
    let Some(Message::Binary(frame)) = frames.recv().await else {
        panic!("no result frame");
    };
    let (client_id, payload) = relay_wire::unwrap(&frame).unwrap();
    assert_eq!(client_id, MCP_CLIENT_ID);
    serde_json::from_slice(payload).unwrap()
}

#[cfg(unix)]
#[tokio::test]
async fn verified_call_runs_the_tool_and_answers_once() {
    let key = SigningKey::from_bytes(&[7; 32]);
    let (verifier, server) = jwks_origin(&key).await;
    let link = link(McpAccess::Read, verifier);
    let result = call(
        &link,
        "call-1",
        call_grant(&key, json!({})),
        "runtime_status",
    )
    .await;
    assert_eq!(result["type"], "mcp.result");
    assert_eq!(result["id"], "call-1");
    assert_eq!(result["result"]["isError"], false);
    let text = result["result"]["content"][0]["text"].as_str().unwrap();
    assert!(
        text.contains("runtime --runtime-dir=/tmp/runtime --json status"),
        "{text}"
    );
    let replay = call(
        &link,
        "call-1",
        call_grant(&key, json!({})),
        "runtime_status",
    )
    .await;
    assert_eq!(replay["error"]["code"], "call_grant_invalid");
    server.abort();
}

#[tokio::test]
async fn grants_for_another_runtime_tool_or_signer_are_refused() {
    let key = SigningKey::from_bytes(&[7; 32]);
    let (verifier, server) = jwks_origin(&key).await;
    let link = link(McpAccess::Full, verifier);
    let other_runtime = call_grant(&key, json!({ "runtimeId": "elsewhere", "jti": "a" }));
    assert_eq!(
        call(&link, "a", other_runtime, "runtime_status").await["error"]["code"],
        "call_grant_invalid"
    );
    let other_tool = call_grant(&key, json!({ "jti": "b" }));
    assert_eq!(
        call(&link, "b", other_tool, "list_projects").await["error"]["code"],
        "call_grant_invalid"
    );
    let forged = call_grant(&SigningKey::from_bytes(&[8; 32]), json!({ "jti": "c" }));
    assert_eq!(
        call(&link, "c", forged, "runtime_status").await["error"]["code"],
        "call_grant_invalid"
    );
    server.abort();
}

#[tokio::test]
async fn execute_tools_need_an_execute_grant_and_full_control() {
    let key = SigningKey::from_bytes(&[7; 32]);
    let (verifier, server) = jwks_origin(&key).await;
    let read_grant = call_grant(&key, json!({ "jti": "d", "tool": "cancel_task" }));
    let full = link(McpAccess::Full, verifier.clone());
    assert_eq!(
        call(&full, "d", read_grant, "cancel_task").await["error"]["code"],
        "access_denied"
    );
    let execute_grant = call_grant(
        &key,
        json!({ "jti": "e", "tool": "cancel_task", "access": "execute" }),
    );
    let read_only = link(McpAccess::Read, verifier);
    assert_eq!(
        call(&read_only, "e", execute_grant, "cancel_task").await["error"]["code"],
        "runtime_read_only"
    );
    server.abort();
}

#[tokio::test]
async fn unknown_tools_report_an_update_hint() {
    let key = SigningKey::from_bytes(&[7; 32]);
    let (verifier, server) = jwks_origin(&key).await;
    let link = link(McpAccess::Full, verifier);
    let grant = call_grant(&key, json!({ "jti": "f", "tool": "future_tool" }));
    let result = call(&link, "f", grant, "future_tool").await;
    assert_eq!(result["error"]["code"], "tool_unavailable");
    server.abort();
}

#[tokio::test]
async fn unreadable_calls_are_answered_instead_of_left_waiting() {
    let key = SigningKey::from_bytes(&[7; 32]);
    let (verifier, server) = jwks_origin(&key).await;
    let link = link(McpAccess::Full, verifier);
    let (control, mut frames) = mpsc::channel(4);
    let payload = br#"{"type":"mcp.call","id":"g","grant":5}"#;
    link.handle_frame(
        payload,
        CallContext {
            account_id: "account",
            runtime_id: "runtime",
            control: &control,
        },
    );
    let Some(Message::Binary(frame)) = frames.recv().await else {
        panic!("no result frame");
    };
    let (_, payload) = relay_wire::unwrap(&frame).unwrap();
    let result: Value = serde_json::from_slice(payload).unwrap();
    assert_eq!(result["id"], "g");
    assert_eq!(result["error"]["code"], "invalid_call");
    server.abort();
}

#[tokio::test]
async fn calls_stop_once_the_link_lifetime_ends() {
    let key = SigningKey::from_bytes(&[7; 32]);
    let (verifier, server) = jwks_origin(&key).await;
    let (link, lifetime) = owned_link(McpAccess::Full, verifier);
    drop(lifetime);
    let grant = call_grant(&key, json!({ "jti": "h" }));
    let result = call(&link, "h", grant, "runtime_status").await;
    assert_eq!(result["error"]["code"], "runtime_unavailable");
    server.abort();
}

#[cfg(unix)]
#[tokio::test]
async fn metadata_document_clients_with_long_ids_can_call_tools() {
    let key = SigningKey::from_bytes(&[7; 32]);
    let (verifier, server) = jwks_origin(&key).await;
    let link = link(McpAccess::Read, verifier);
    let client_id = format!("https://client.example/{}.json", "a".repeat(400));
    let grant = call_grant(&key, json!({ "jti": "i", "clientId": client_id }));
    let result = call(&link, "i", grant, "runtime_status").await;
    assert_eq!(result["result"]["isError"], false, "{result}");
    server.abort();
}
