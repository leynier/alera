use super::*;
use crate::terminal_host::protocol::{
    PROTOCOL_VERSION, RUNTIME_HOST_BOOTSTRAP_CAPABILITY, RUNTIME_HOST_CAPABILITY,
    RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::task::JoinHandle;

/// A host that answers `hello` and then `workspace.focus` with `answer`.
async fn fake_host(dir: &Path, focus_capability: bool, answer: Value) -> JoinHandle<Option<Value>> {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let mut capabilities = vec![
        RUNTIME_HOST_CAPABILITY,
        RUNTIME_HOST_BOOTSTRAP_CAPABILITY,
        RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,
    ];
    if focus_capability {
        capabilities.push(RUNTIME_HOST_WORKSPACE_FOCUS_CAPABILITY);
    }
    std::fs::write(
        dir.join("host.json"),
        serde_json::to_vec(&json!({
            "protocolVersion": PROTOCOL_VERSION,
            "port": port,
            "token": "fixture-token",
            "runtimeCapabilities": capabilities,
        }))
        .unwrap(),
    )
    .unwrap();
    tokio::spawn(async move {
        let (stream, _) = listener.accept().await.unwrap();
        let (read, mut write) = stream.into_split();
        let mut lines = BufReader::new(read).lines();
        let mut focus_payload = None;
        while let Ok(Some(line)) = lines.next_line().await {
            let request: Value = serde_json::from_str(&line).unwrap();
            let frame = if request["type"] == "hello" {
                json!({"id": request["id"], "ok": true, "payload": {}})
            } else {
                assert_eq!(request["type"], "workspace.focus");
                focus_payload = Some(request["payload"].clone());
                let mut frame = answer.clone();
                frame["id"] = request["id"].clone();
                frame
            };
            write
                .write_all(format!("{frame}\n").as_bytes())
                .await
                .unwrap();
        }
        focus_payload
    })
}

#[tokio::test]
async fn reports_that_alera_is_not_running_without_starting_a_host() {
    let dir = tempfile::tempdir().unwrap();

    let error = focus(dir.path(), "w").await.unwrap_err();

    assert!(
        error.to_string().contains("Alera is not running"),
        "{error}"
    );
    assert!(!dir.path().join("host.json").exists());
}

#[tokio::test]
async fn sends_workspace_focus_to_a_live_host() {
    let dir = tempfile::tempdir().unwrap();
    let answer = json!({"workspaceId": "w", "projectId": "p", "name": "Checkout", "appClients": 1});
    let host = fake_host(
        dir.path(),
        true,
        json!({"ok": true, "payload": answer.clone()}),
    )
    .await;

    let value = focus(dir.path(), "w").await.unwrap();

    assert_eq!(value, answer);
    assert_eq!(host.await.unwrap(), Some(json!({"workspaceId": "w"})));
    assert_eq!(
        focus_summary(&value),
        "focus requested for Checkout in Alera"
    );
}

#[tokio::test]
async fn surfaces_the_host_refusal() {
    let dir = tempfile::tempdir().unwrap();
    let _host = fake_host(
        dir.path(),
        true,
        json!({"ok": false, "error": "No Alera desktop app is connected to this runtime."}),
    )
    .await;

    let error = focus(dir.path(), "w").await.unwrap_err();

    assert!(
        error
            .to_string()
            .contains("No Alera desktop app is connected"),
        "{error}"
    );
}

#[tokio::test]
async fn refuses_a_live_host_that_predates_workspace_focus() {
    let dir = tempfile::tempdir().unwrap();
    let host = fake_host(dir.path(), false, json!({"ok": true, "payload": {}})).await;

    let error = focus(dir.path(), "w").await.unwrap_err();

    assert!(
        error
            .to_string()
            .contains("does not support workspaceFocusV1"),
        "{error}"
    );
    assert_eq!(host.await.unwrap(), None, "no focus request was sent");
}

#[test]
fn summary_falls_back_to_the_workspace_id() {
    assert_eq!(
        focus_summary(&json!({"workspaceId": "w-1"})),
        "focus requested for w-1 in Alera"
    );
}
