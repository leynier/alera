use super::super::{actor_test_harness::test_actor, ClientState, ServerCommand};
use super::*;
use crate::terminal_host::client::ClientHandle;
use crate::terminal_host::host_link_registry::HostLinkRegistry;
use std::sync::atomic::{AtomicUsize, Ordering};
use tokio::sync::mpsc;

const SATELLITE: &str = r#"
printf '%s\n' '{"event":"hostLink.attached","payload":{"runtimeDir":"/sat/data","platform":"linux","arch":"x86_64","runtimeCapabilities":["agentChatRemoteProviderSetupV1"]}}'
while IFS= read -r line; do
  printf '{"event":"setupProbe","payload":%s}\n' "$line"
  id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')
  case "$line" in
    *'"type":"createOrAttach"'*) printf '{"id":%s,"ok":false,"errorCode":"unsupported","error":"Unsupported setup"}\n' "$id" ;;
    *'"type":"terminate"'*) printf '{"id":%s,"ok":false,"error":"Ambiguous close failure"}\n' "$id" ;;
    *) printf '{"id":%s,"ok":true,"payload":{}}\n' "$id" ;;
  esac
done
"#;

fn setup_request(operation: &str) -> Value {
    json!({"type":operation,"providerSetup":{"providerInstanceId":"codex","action":"signIn"},
        "payload":{"sessionId":"__alera_provider_setup__:setup","workspaceId":SETUP_WORKSPACE_ID,"tabId":"setup",
            "launch":{"providerSetup":{"providerInstanceId":"codex","action":"signIn"}}}})
}

async fn fixture() -> (
    tempfile::TempDir,
    ServerActor,
    super::super::ServerInboxReceiver,
    Arc<AtomicUsize>,
) {
    let root = tempfile::tempdir().unwrap();
    let (control, _) = mpsc::unbounded_channel();
    let (terminal, _) = mpsc::channel(8);
    let desktop = ClientState::local(ClientHandle::new(control, terminal), true);
    let mut actor = test_actor(&root, HashMap::from([(10, desktop)]), HashMap::new()).await;
    crate::terminal_host::host_link::tests::live::stored_target(&actor.runtime_store).await;
    let (inbox, events) = crate::terminal_host::ServerInbox::channel();
    let launches = Arc::new(AtomicUsize::new(0));
    let count = launches.clone();
    let original = crate::terminal_host::host_link::tests::live::fake_launcher(SATELLITE);
    actor.host_links = HostLinkRegistry::with_launcher(
        actor.runtime_store.clone(),
        inbox,
        Arc::new(move |target| {
            count.fetch_add(1, Ordering::SeqCst);
            original(target)
        }),
    );
    (root, actor, events, launches)
}

async fn probe(events: &mut super::super::ServerInboxReceiver) -> Value {
    tokio::time::timeout(std::time::Duration::from_secs(2), async {
        loop {
            if let Some(ServerCommand::HostLinkEvent { event, .. }) = events.recv().await {
                if event["event"] == "setupProbe" {
                    break event["payload"].clone();
                }
            }
        }
    })
    .await
    .unwrap()
}

#[tokio::test]
async fn definitive_failed_launch_retires_busy_route_and_releases_exact_lease() {
    let (_root, actor, mut events, _) = fixture().await;
    let forwarded = actor
        .forwarded_provider_setup_payload("lab", 10, &setup_request("createOrAttach"))
        .unwrap();
    let error = forward_setup_request(
        actor.host_links.clone(),
        "lab".into(),
        forwarded.clone(),
        std::time::Duration::from_secs(2),
    )
    .await
    .unwrap_err();
    assert!(matches!(error, HostError::Conflict { code, .. } if code == "unsupported"));
    assert!(!actor.host_links.provider_setup_sessions.has_host("lab"));
    assert_eq!(
        probe(&mut events).await["payload"]["type"],
        "createOrAttach"
    );
    let released = probe(&mut events).await;
    assert_eq!(released["payload"]["type"], "terminate");
    assert_eq!(
        released["payload"]["desktopLeaseId"],
        forwarded["desktopLeaseId"]
    );
    actor.host_links.disconnect_all().await;
}

#[tokio::test]
async fn failed_close_retires_active_route_retries_exact_lease_and_preserves_error() {
    let (_root, actor, mut events, _) = fixture().await;
    actor
        .forwarded_provider_setup_payload("lab", 10, &setup_request("createOrAttach"))
        .unwrap();
    let forwarded = actor
        .forwarded_provider_setup_payload("lab", 10, &setup_request("terminate"))
        .unwrap();
    let error = forward_setup_request(
        actor.host_links.clone(),
        "lab".into(),
        forwarded.clone(),
        std::time::Duration::from_secs(2),
    )
    .await
    .unwrap_err();
    assert_eq!(error.wire_message(), "Ambiguous close failure");
    assert!(!actor.host_links.provider_setup_sessions.has_host("lab"));
    let original = probe(&mut events).await;
    let retry = probe(&mut events).await;
    for key in ["type", "providerSetup", "desktopClientId", "desktopLeaseId"] {
        assert_eq!(original["payload"][key], retry["payload"][key]);
    }
    assert_eq!(
        original["payload"]["payload"]["sessionId"],
        retry["payload"]["payload"]["sessionId"]
    );
    assert_eq!(
        retry["payload"]["desktopLeaseId"],
        forwarded["desktopLeaseId"]
    );
    actor.host_links.disconnect_all().await;
}

#[tokio::test]
async fn host_removal_closes_only_registered_setups_on_the_captured_link() {
    let (_root, actor, mut events, launches) = fixture().await;
    let forwarded = actor
        .forwarded_provider_setup_payload("lab", 10, &setup_request("createOrAttach"))
        .unwrap();
    actor.host_links.link("lab").await.unwrap();
    actor.host_links.drop_host("lab").await;
    assert_eq!(launches.load(Ordering::SeqCst), 1);
    assert!(!actor.host_links.provider_setup_sessions.has_host("lab"));
    let request = probe(&mut events).await;
    assert_eq!(request["type"], INTERNAL_SETUP_REQUEST);
    assert_eq!(request["payload"]["type"], FORCE_CLOSE_OPERATION);
    assert_eq!(
        request["payload"]["providerSetup"],
        forwarded["providerSetup"]
    );
    assert_eq!(
        request["payload"]["payload"]["sessionId"],
        "__alera_provider_setup__:setup"
    );
    assert!(actor.host_links.attached_link("lab").is_none());
    let mut spoof = setup_request(FORCE_CLOSE_OPERATION);
    spoof["desktopClientId"] = json!(10);
    assert!(actor
        .forwarded_provider_setup_payload("lab", 10, &spoof)
        .is_err());
}

async fn gated_fixture(
    before_attach: bool,
) -> (
    tempfile::TempDir,
    ServerActor,
    super::super::ServerInboxReceiver,
    Arc<tokio::sync::Notify>,
    std::path::PathBuf,
) {
    let (root, mut actor, _, _) = fixture().await;
    let gate = root.path().join("release-setup");
    let wait = format!("while [ ! -f '{}' ]; do sleep 0.01; done\n", gate.display());
    let script = format!(
        "{}{}{}",
        if before_attach {
            wait.clone()
        } else {
            String::new()
        },
        r#"printf '%s\n' '{"event":"hostLink.attached","payload":{"runtimeDir":"/sat/data","platform":"linux","arch":"x86_64","runtimeCapabilities":["agentChatRemoteProviderSetupV1"]}}'
"#,
        r#"while IFS= read -r line; do
  printf '{"event":"setupProbe","payload":%s}\n' "$line"
  case "$line" in *'"type":"createOrAttach"'*) __WAIT_CREATE__ ;; esac
  id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')
  printf '{"id":%s,"ok":true,"payload":{"created":true}}\n' "$id"
done
"#
        .replace(
            "__WAIT_CREATE__",
            if before_attach { ":" } else { wait.trim() }
        )
    );
    let started = Arc::new(tokio::sync::Notify::new());
    let signal = started.clone();
    let (inbox, events) = crate::terminal_host::ServerInbox::channel();
    actor.host_links = HostLinkRegistry::with_launcher(
        actor.runtime_store.clone(),
        inbox,
        Arc::new(move |_| {
            signal.notify_one();
            let mut command = alera_core::child_process::windowless_async_command("sh");
            command.arg("-c").arg(script.clone());
            Ok(command)
        }),
    );
    (root, actor, events, started, gate)
}

#[tokio::test]
async fn disposed_lease_waiting_for_link_never_sends_a_late_create() {
    let (_root, actor, mut events, started, gate) = gated_fixture(true).await;
    let envelope = actor
        .forwarded_provider_setup_payload("lab", 10, &setup_request("createOrAttach"))
        .unwrap();
    let links = actor.host_links.clone();
    let request = tokio::spawn(forward_setup_request(
        links,
        "lab".into(),
        envelope.clone(),
        std::time::Duration::from_secs(2),
    ));
    started.notified().await;
    actor.cleanup_remote_provider_setup_client(10);
    tokio::fs::write(gate, b"ready").await.unwrap();
    assert!(request.await.unwrap().is_err());
    let cleanup = probe(&mut events).await;
    assert_eq!(cleanup["payload"]["type"], "terminate");
    assert_eq!(
        cleanup["payload"]["desktopLeaseId"],
        envelope["desktopLeaseId"]
    );
    assert!(!actor.host_links.provider_setup_sessions.has_host("lab"));
    actor.host_links.disconnect_all().await;
}

#[tokio::test]
async fn disposed_lease_with_create_in_flight_is_revoked_after_the_late_reply() {
    let (_root, actor, mut events, _, gate) = gated_fixture(false).await;
    let envelope = actor
        .forwarded_provider_setup_payload("lab", 10, &setup_request("createOrAttach"))
        .unwrap();
    let links = actor.host_links.clone();
    let request = tokio::spawn(forward_setup_request(
        links,
        "lab".into(),
        envelope.clone(),
        std::time::Duration::from_secs(2),
    ));
    assert_eq!(
        probe(&mut events).await["payload"]["type"],
        "createOrAttach"
    );
    actor.cleanup_remote_provider_setup_client(10);
    tokio::fs::write(gate, b"ready").await.unwrap();
    assert!(request.await.unwrap().is_err());
    for _ in 0..2 {
        let cleanup = probe(&mut events).await;
        assert_eq!(cleanup["payload"]["type"], "terminate");
        assert_eq!(
            cleanup["payload"]["desktopLeaseId"],
            envelope["desktopLeaseId"]
        );
    }
    assert!(!actor.host_links.provider_setup_sessions.has_host("lab"));
    actor.host_links.disconnect_all().await;
}
