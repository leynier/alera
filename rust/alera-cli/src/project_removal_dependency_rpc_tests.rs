use super::prepare_cli_project_removal_dependencies;
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::{
    PROTOCOL_VERSION, RUNTIME_HOST_BOOTSTRAP_CAPABILITY, RUNTIME_HOST_CAPABILITY,
    RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY, RUNTIME_HOST_SHARED_CHECKOUT_CAPABILITY,
};
use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

async fn dependency_server(
    sequence: Vec<(&'static str, Value)>,
) -> (
    tempfile::TempDir,
    RuntimeHostRpcClient,
    tokio::task::JoinHandle<()>,
) {
    let directory = tempfile::tempdir().unwrap();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    std::fs::write(
        directory.path().join("host.json"),
        serde_json::to_vec(&json!({
            "protocolVersion": PROTOCOL_VERSION, "port":port, "token":"fixture-token",
            "runtimeCapabilities":[RUNTIME_HOST_CAPABILITY, RUNTIME_HOST_SHARED_CHECKOUT_CAPABILITY,
                RUNTIME_HOST_BOOTSTRAP_CAPABILITY, RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY]
        }))
        .unwrap(),
    )
    .unwrap();
    let server = tokio::spawn(async move {
        let (stream, _) = listener.accept().await.unwrap();
        let (read, mut write) = stream.into_split();
        let mut lines = BufReader::new(read).lines();
        for (expected, payload) in std::iter::once(("hello", json!({}))).chain(sequence) {
            let line = lines.next_line().await.unwrap().unwrap();
            let request: Value = serde_json::from_str(&line).unwrap();
            assert_eq!(request["type"], expected);
            if expected == "automation.pause" {
                assert_eq!(request["payload"]["id"], "approved");
                assert_eq!(request["payload"]["activeRuns"], "cancel-active");
            }
            let response = json!({"id":request["id"],"ok":true,"payload":payload});
            write
                .write_all(format!("{response}\n").as_bytes())
                .await
                .unwrap();
        }
        assert!(
            lines.next_line().await.unwrap().is_none(),
            "unexpected mutation after dependency handling"
        );
    });
    let client = RuntimeHostRpcClient::connect(directory.path())
        .await
        .unwrap()
        .unwrap();
    (directory, client, server)
}

fn dependency(id: &str, requires_pause: bool) -> Value {
    json!({"id":id,"name":"Task Automation","activeRuns":usize::from(requires_pause),"requiresPause":requires_pause})
}

#[tokio::test]
async fn project_dependency_rpc_without_confirmation_sends_no_pause() {
    let (_directory, mut client, server) = dependency_server(vec![(
        "project.removalDependencies",
        json!([dependency("approved", true)]),
    )])
    .await;
    let error = prepare_cli_project_removal_dependencies(&mut client, "project", false)
        .await
        .unwrap_err();
    assert!(error
        .to_string()
        .contains("--pause-automations-and-cancel-runs"));
    drop(client);
    server.await.unwrap();
}

#[tokio::test]
async fn project_dependency_rpc_waits_for_confirmed_automation_cancellation() {
    let (_directory, mut client, server) = dependency_server(vec![
        (
            "project.removalDependencies",
            json!([dependency("approved", true)]),
        ),
        ("automation.pause", json!({})),
        (
            "project.removalDependencies",
            json!([dependency("approved", false)]),
        ),
    ])
    .await;
    prepare_cli_project_removal_dependencies(&mut client, "project", true)
        .await
        .unwrap();
    drop(client);
    server.await.unwrap();
}

#[tokio::test]
async fn project_dependency_rpc_refuses_new_dependencies_outside_confirmed_scope() {
    let (_directory, mut client, server) = dependency_server(vec![
        (
            "project.removalDependencies",
            json!([dependency("approved", true)]),
        ),
        ("automation.pause", json!({})),
        (
            "project.removalDependencies",
            json!([dependency("new", true)]),
        ),
    ])
    .await;
    let error = prepare_cli_project_removal_dependencies(&mut client, "project", true)
        .await
        .unwrap_err();
    assert!(error.to_string().contains("dependencies changed"));
    drop(client);
    server.await.unwrap();
}
