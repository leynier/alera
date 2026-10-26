use super::super::actor_test_harness::{local_client, mobile_client, test_actor};
use super::super::ClientState;
use super::*;
use crate::terminal_host::client::ClientHandle;
use crate::terminal_host::session::Session;
use tokio::sync::mpsc;

fn envelope(operation: &str) -> Value {
    json!({
        "type": operation,
        "providerSetup": {"providerInstanceId":"codex", "action":"signIn"},
        "payload": {"sessionId":"__alera_provider_setup__:setup-session", "tabId":"setup-session", "workspaceId":SETUP_WORKSPACE_ID,
            "launch":{"providerSetup":{"providerInstanceId":"codex","action":"signIn"}}, "cols":100, "rows":30},
        "desktopClientId": 10,
        "desktopLeaseId":"00000000-0000-4000-8000-000000000010",
    })
}

#[test]
fn setup_route_pins_host_selection_and_attachment_before_input() {
    let routes = RemoteSetupSessions::default();
    assert!(routes.admit("owner", 10, &envelope("write")).is_err());
    routes
        .admit("owner", 10, &envelope("createOrAttach"))
        .unwrap();
    routes.admit("owner", 10, &envelope("write")).unwrap();
    assert!(routes
        .admit("another", 10, &envelope("createOrAttach"))
        .is_err());
    let mut changed = envelope("createOrAttach");
    changed["providerSetup"]["action"] = json!("install");
    assert!(routes.admit("owner", 10, &changed).is_err());
    assert!(routes.admit("owner", 11, &envelope("write")).is_err());
    routes
        .admit("owner", 11, &envelope("createOrAttach"))
        .unwrap();
    assert!(routes.has_host("owner"));
    assert!(routes
        .release("__alera_provider_setup__:setup-session", 10)
        .is_some());
    routes.release("__alera_provider_setup__:setup-session", 11);
    assert_eq!(
        routes.clients("owner", "__alera_provider_setup__:setup-session"),
        None
    );
}

#[test]
fn setup_route_refuses_nonterminal_operations_and_recipe_fields() {
    let routes = RemoteSetupSessions::default();
    assert!(routes
        .admit("owner", 10, &envelope("host.shutdown"))
        .is_err());
    let mut request = envelope("createOrAttach");
    request["providerSetup"]["environment"] = json!({"TOKEN":"untrusted"});
    assert!(routes.admit("owner", 10, &request).is_err());
}

#[test]
fn shared_setup_stays_busy_until_the_last_client_disposes() {
    let routes = RemoteSetupSessions::default();
    routes
        .admit("owner", 10, &envelope("createOrAttach"))
        .unwrap();
    routes
        .admit("owner", 11, &envelope("createOrAttach"))
        .unwrap();
    assert_eq!(routes.forget_client(10).len(), 1);
    assert!(routes.has_host("owner"));
    let retired = routes.forget_client(11);
    assert_eq!(retired.len(), 1);
    assert_eq!(retired[0].host_id, "owner");
    assert_eq!(
        retired[0].session_id,
        "__alera_provider_setup__:setup-session"
    );
    assert_eq!(
        retired[0].selection,
        ProviderSetupContext::from_json(&envelope("write")["providerSetup"]).unwrap()
    );
    assert!(!routes.has_host("owner"));
    routes
        .admit("owner", 10, &envelope("createOrAttach"))
        .unwrap();
    routes.forget_host("owner");
    assert!(!routes.has_host("owner"));
}

#[tokio::test]
async fn forwarding_derives_human_authority_and_denies_reverse_phone_and_cli_spoofs() {
    let root = tempfile::tempdir().unwrap();
    let client = |app| {
        let (control, _) = mpsc::unbounded_channel();
        let (terminal, _) = mpsc::channel(1);
        ClientState::local(ClientHandle::new(control, terminal), app)
    };
    let (control, _) = mpsc::unbounded_channel();
    let (terminal, _) = mpsc::channel(1);
    let phone = mobile_client(ClientHandle::new(control, terminal), "phone");
    let mut actor = test_actor(
        &root,
        HashMap::from([(10, client(true)), (11, client(false)), (12, phone)]),
        HashMap::new(),
    )
    .await;
    let mut forged = envelope("createOrAttach");
    forged["desktopClientId"] = json!(999);
    assert_eq!(
        actor
            .forwarded_provider_setup_payload("owner", 10, &forged)
            .unwrap()["desktopClientId"],
        10
    );
    assert!(actor
        .forwarded_provider_setup_payload("owner", 11, &forged)
        .is_err());
    assert!(actor
        .forwarded_provider_setup_payload("owner", 12, &forged)
        .is_err());
    actor
        .try_handle_hub_reverse_request(10, 1, "hub.link.register", &json!({}))
        .unwrap();
    assert!(actor
        .forwarded_provider_setup_payload("owner", 10, &forged)
        .is_err());
    for id in [10, 11, 12] {
        actor.forget_hub_reverse_client(10);
        assert!(actor
            .try_handle_remote_provider_setup(id, 1, INTERNAL_SETUP_REQUEST, &forged)
            .await
            .is_err());
    }
}

#[tokio::test]
async fn owner_allows_attached_hub_input_and_resize_without_opening_raw_setup_access() {
    let root = tempfile::tempdir().unwrap();
    let (control, _) = mpsc::unbounded_channel();
    let (terminal, _) = mpsc::channel(8);
    let hub = local_client(ClientHandle::new(control, terminal));
    let mut session = Session::driver_test_stub("__alera_provider_setup__:setup-session", 80, 24);
    session.workspace_id = SETUP_WORKSPACE_ID.into();
    session.provider_setup =
        Some(ProviderSetupContext::from_json(&envelope("resize")["providerSetup"]).unwrap());
    session.attach(1);
    session
        .provider_setup_desktop_leases
        .insert("00000000-0000-4000-8000-000000000010".into(), 10);
    // Paused output must not revoke an attached desktop's input authority.
    session.set_output_paused(1, true);
    let input = session.attach_test_input();
    let mut actor = test_actor(
        &root,
        HashMap::from([(1, hub)]),
        HashMap::from([("__alera_provider_setup__:setup-session".into(), session)]),
    )
    .await;
    actor
        .try_handle_hub_reverse_request(1, 1, "hub.link.register", &json!({}))
        .unwrap();
    assert!(actor
        .try_handle_remote_provider_setup(1, 2, INTERNAL_SETUP_REQUEST, &envelope("resize"))
        .await
        .unwrap());
    assert_eq!(
        actor.sessions["__alera_provider_setup__:setup-session"].current_dims,
        (100, 30)
    );
    let mut write = envelope("write");
    write["payload"]["dataBase64"] = json!(crate::terminal_host::protocol::encode_bytes(b"answer"));
    assert!(actor
        .try_handle_remote_provider_setup(1, 3, INTERNAL_SETUP_REQUEST, &write)
        .await
        .unwrap());
    assert_eq!(
        input
            .recv_timeout(std::time::Duration::from_secs(1))
            .unwrap()
            .bytes,
        b"answer"
    );
    assert!(actor
        .handle_request(1, "resize", &envelope("resize")["payload"])
        .await
        .is_err());
    let mut changed = envelope("resize");
    changed["providerSetup"]["providerInstanceId"] = json!("another");
    assert!(actor
        .try_handle_remote_provider_setup(1, 4, INTERNAL_SETUP_REQUEST, &changed)
        .await
        .is_err());
    actor
        .sessions
        .get_mut("__alera_provider_setup__:setup-session")
        .unwrap()
        .provider_setup = None;
    assert!(actor
        .try_handle_remote_provider_setup(1, 5, INTERNAL_SETUP_REQUEST, &envelope("resize"))
        .await
        .is_err());
}

#[tokio::test]
async fn delayed_old_cleanup_preserves_new_attachment_and_rejects_old_unleased_input() {
    let root = tempfile::tempdir().unwrap();
    let (control, _) = mpsc::unbounded_channel();
    let (terminal, _) = mpsc::channel(8);
    let hub = local_client(ClientHandle::new(control, terminal));
    let mut session = Session::driver_test_stub("__alera_provider_setup__:setup-session", 80, 24);
    session.workspace_id = SETUP_WORKSPACE_ID.into();
    session.tab_id = "setup-session".into();
    session.provider_setup =
        Some(ProviderSetupContext::from_json(&envelope("resize")["providerSetup"]).unwrap());
    session
        .provider_setup_desktop_leases
        .insert("00000000-0000-4000-8000-000000000010".into(), 10);
    session.attach(1);
    let mut actor = test_actor(
        &root,
        HashMap::from([(1, hub)]),
        HashMap::from([("__alera_provider_setup__:setup-session".into(), session)]),
    )
    .await;
    actor
        .try_handle_hub_reverse_request(1, 1, "hub.link.register", &json!({}))
        .unwrap();
    let service = super::super::agent_chat_provider_settings::ProviderSettingsService::new(
        actor.runtime_store.clone(),
        Arc::new(super::super::agent_chat_runtime::InstanceDirectory::default()),
        root.path(),
        "setup-test",
        Arc::new(|_, _| {}),
    );
    service.initialize().await.unwrap();
    actor.agent_chat_provider_settings = Some(service);
    let mut new_attachment = envelope("createOrAttach");
    new_attachment["desktopClientId"] = json!(11);
    new_attachment["desktopLeaseId"] = json!("00000000-0000-4000-8000-000000000011");
    actor
        .try_handle_remote_provider_setup(1, 2, INTERNAL_SETUP_REQUEST, &new_attachment)
        .await
        .unwrap();
    actor
        .try_handle_remote_provider_setup(1, 3, INTERNAL_SETUP_REQUEST, &envelope("terminate"))
        .await
        .unwrap();
    assert!(actor.sessions["__alera_provider_setup__:setup-session"].running());
    assert_eq!(
        actor.sessions["__alera_provider_setup__:setup-session"]
            .provider_setup_desktop_leases
            .len(),
        1
    );
    assert!(actor
        .try_handle_remote_provider_setup(1, 4, INTERNAL_SETUP_REQUEST, &envelope("resize"))
        .await
        .is_err());
    // The same old cleanup replay cannot terminate the new lease.
    actor
        .try_handle_remote_provider_setup(1, 5, INTERNAL_SETUP_REQUEST, &envelope("terminate"))
        .await
        .unwrap();
    assert!(actor.sessions["__alera_provider_setup__:setup-session"].running());
    new_attachment["type"] = json!("terminate");
    actor
        .try_handle_remote_provider_setup(1, 6, INTERNAL_SETUP_REQUEST, &new_attachment)
        .await
        .unwrap();
    assert!(!actor
        .sessions
        .contains_key("__alera_provider_setup__:setup-session"));
}

#[tokio::test]
async fn setup_output_reaches_only_its_admitted_desktop() {
    let root = tempfile::tempdir().unwrap();
    let (control, mut owner_events) = mpsc::unbounded_channel();
    let (terminal, _) = mpsc::channel(8);
    let desktop = ClientState::local(ClientHandle::new(control, terminal), true);
    let (control, mut other_events) = mpsc::unbounded_channel();
    let (terminal, _) = mpsc::channel(8);
    let other = ClientState::local(ClientHandle::new(control, terminal), true);
    let actor = test_actor(
        &root,
        HashMap::from([(10, desktop), (11, other)]),
        HashMap::new(),
    )
    .await;
    actor
        .forwarded_provider_setup_payload("owner", 10, &envelope("createOrAttach"))
        .unwrap();
    assert!(actor.relay_provider_setup_event(
        "owner",
        "output",
        &json!({"sessionId":"__alera_provider_setup__:setup-session","dataBase64":"b3V0cHV0"})
    ));
    assert!(owner_events.try_recv().is_ok());
    assert!(other_events.try_recv().is_err());
    actor
        .host_links
        .provider_setup_sessions
        .release("__alera_provider_setup__:setup-session", 10);
    assert!(actor.relay_provider_setup_event(
        "owner",
        "output",
        &json!({"sessionId":"__alera_provider_setup__:setup-session","dataBase64":"b3V0cHV0"})
    ));
    assert!(owner_events.try_recv().is_err());
}

#[cfg(unix)]
#[tokio::test]
async fn disposing_last_desktop_terminates_only_its_exact_owner_setup_terminal() {
    const SATELLITE: &str = r#"
printf '%s\n' '{"event":"hostLink.attached","payload":{"runtimeDir":"/sat/data","platform":"linux","arch":"x86_64","runtimeCapabilities":["agentChatRemoteProviderSetupV1"]}}'
while IFS= read -r line; do
  printf '{"event":"setupCleanupProbe","payload":%s}\n' "$line"
  id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')
  printf '{"id":%s,"ok":true,"payload":{}}\n' "$id"
done
"#;
    let root = tempfile::tempdir().unwrap();
    let (control, _) = mpsc::unbounded_channel();
    let (terminal, _) = mpsc::channel(8);
    let client = ClientState::local(ClientHandle::new(control, terminal), true);
    let ordinary = Session::driver_test_stub("ordinary-session", 80, 24);
    let mut actor = test_actor(
        &root,
        HashMap::from([(10, client)]),
        HashMap::from([("ordinary-session".into(), ordinary)]),
    )
    .await;
    crate::terminal_host::host_link::tests::live::stored_target(&actor.runtime_store).await;
    let (inbox, mut requests) = crate::terminal_host::ServerInbox::channel();
    actor.host_links = crate::terminal_host::host_link_registry::HostLinkRegistry::with_launcher(
        actor.runtime_store.clone(),
        inbox,
        crate::terminal_host::host_link::tests::live::fake_launcher(SATELLITE),
    );
    actor
        .forwarded_provider_setup_payload("lab", 10, &envelope("createOrAttach"))
        .unwrap();
    assert!(actor.host_links.provider_setup_sessions.has_host("lab"));
    actor.dispose_client(10).await;
    assert!(!actor.host_links.provider_setup_sessions.has_host("lab"));
    let frame = tokio::time::timeout(std::time::Duration::from_secs(2), async {
        loop {
            if let Some(super::super::ServerCommand::HostLinkEvent { event, .. }) =
                requests.recv().await
            {
                if event["event"] == "setupCleanupProbe" {
                    break event["payload"].clone();
                }
            }
        }
    })
    .await
    .unwrap();
    assert_eq!(frame["type"], INTERNAL_SETUP_REQUEST);
    assert_eq!(frame["payload"]["type"], "terminate");
    assert_eq!(
        frame["payload"]["payload"]["sessionId"],
        "__alera_provider_setup__:setup-session"
    );
    assert_eq!(
        frame["payload"]["providerSetup"],
        envelope("write")["providerSetup"]
    );
    assert!(actor.sessions["ordinary-session"].running());
    actor.host_links.disconnect_all().await;
}
