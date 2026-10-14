use super::super::agent_chat_remote::tests::remote_fixture;
use super::super::agent_chat_runtime::events::NullSink;
use super::super::agent_chat_runtime::{InstanceDirectory, ProductionProviderFactory};
use super::super::chat_orchestration::{ChatCredentialLaunchHook, RuntimeTargetResolver};
use super::*;

pub(super) async fn service_fixture() -> (
    tempfile::TempDir,
    RemoteChatRouter,
    Arc<super::super::agent_chat_remote::tests::FakeChatHost>,
    Arc<RoutedChatRuntime>,
    ChatOrchestrationService,
) {
    let (root, router, host) = remote_fixture().await;
    let local = AgentChatRuntime::new(
        router.store.clone(),
        Arc::new(ProductionProviderFactory),
        Arc::new(router.store.clone()),
        Box::new(NullSink),
        Arc::new(InstanceDirectory::default()),
    );
    let runtime = RoutedChatRuntime::new(local.clone(), router.clone());
    let credentials =
        ChatCredentialLaunchHook::new(router.store.clone(), root.path().into()).unwrap();
    let service = ChatOrchestrationService::new(
        router.store.clone(),
        local,
        Arc::new(RuntimeTargetResolver::new(router.store.clone())),
        credentials,
    )
    .with_runtime(runtime.clone());
    (root, router, host, runtime, service)
}

fn authority() -> Value {
    json!({"originChatId":"remote-chat", "generation":3, "credentialHash":"a".repeat(64)})
}

#[tokio::test]
async fn forwarding_reconstructs_bound_authority_and_rechecks_revocation_and_live_turn() {
    let (_root, router, host, _runtime, service) = service_fixture().await;
    let payload = json!({"workspaceId":"task", "originChatId":"spoofed-chat", "actor":"desktop", "scope":"desktop", "runtimeMode":"full-access"});
    let answer = answer_remote_orchestration(
        Some(service.clone()),
        router.clone(),
        "satellite",
        "chatOrchestration.capabilities",
        &payload,
        Some(&authority()),
    )
    .await
    .unwrap();
    assert_eq!(answer["caller"]["chatId"], "remote-chat");
    assert_eq!(answer["caller"]["runtimeMode"], "auto");
    assert!(!answer["ceilingRuntimeModes"]
        .as_array()
        .unwrap()
        .contains(&json!("full-access")));
    let check = host
        .calls
        .lock()
        .unwrap()
        .iter()
        .find(|(_, _, payload)| payload["operation"] == "validateBinding")
        .unwrap()
        .2
        .clone();
    assert_eq!(check["chatId"], "remote-chat");
    assert_eq!(check["credentialHash"], "a".repeat(64));
    let ceiling = answer_remote_orchestration(Some(service.clone()), router.clone(), "satellite", "chatOrchestration.delegate", &json!({"requestId":"deny", "task":"brief", "runtimeMode":"full-access", "target":{"workspace":{"workspaceId":"task"}}}), Some(&authority())).await.unwrap_err();
    assert_eq!(ceiling.wire_response(0)["errorCode"], "mode_ceiling");
    let lineage = answer_remote_orchestration(
        Some(service.clone()),
        router.clone(),
        "satellite",
        "chatOrchestration.interrupt",
        &json!({"requestId":"not-owned", "chatId":"unrelated-chat"}),
        Some(&authority()),
    )
    .await
    .unwrap_err();
    assert_eq!(lineage.wire_response(0)["errorCode"], "not_in_lineage");
    *host.credential.lock().unwrap() = None;
    let revoked = answer_remote_orchestration(
        Some(service.clone()),
        router.clone(),
        "satellite",
        "chatOrchestration.capabilities",
        &payload,
        Some(&authority()),
    )
    .await
    .unwrap_err();
    assert_eq!(
        revoked.wire_response(0)["errorCode"],
        "chat_credential_invalid"
    );
    *host.credential.lock().unwrap() = Some(("remote-chat".into(), 3, "a".repeat(64)));
    host.snapshot.lock().unwrap()["session"]["activeTurnId"] = Value::Null;
    let inactive = answer_remote_orchestration(
        Some(service),
        router,
        "satellite",
        "chatOrchestration.capabilities",
        &payload,
        Some(&authority()),
    )
    .await
    .unwrap_err();
    assert_eq!(
        inactive.wire_response(0)["errorCode"],
        "caller_turn_inactive"
    );
}

#[tokio::test]
async fn foreign_host_and_changed_generation_never_get_bound_authority() {
    let (_root, router, host, _runtime, service) = service_fixture().await;
    let payload = json!({"workspaceId":"task"});
    let foreign = answer_remote_orchestration(
        Some(service.clone()),
        router.clone(),
        "foreign-host",
        "chatOrchestration.capabilities",
        &payload,
        Some(&authority()),
    )
    .await
    .unwrap_err();
    assert_eq!(
        foreign.wire_response(0)["errorCode"],
        "chat_credential_invalid"
    );
    assert!(!host
        .calls
        .lock()
        .unwrap()
        .iter()
        .any(|(_, _, payload)| payload["operation"] == "validateBinding"));
    host.snapshot.lock().unwrap()["session"]["generation"] = json!(4);
    let stale = answer_remote_orchestration(
        Some(service),
        router,
        "satellite",
        "chatOrchestration.capabilities",
        &payload,
        Some(&authority()),
    )
    .await
    .unwrap_err();
    assert_eq!(
        stale.wire_response(0)["errorCode"],
        "chat_credential_invalid"
    );
}

#[tokio::test]
async fn payload_identity_without_connection_binding_stays_human() {
    let (_root, router, _host, _runtime, service) = service_fixture().await;
    let answer = answer_remote_orchestration(
        Some(service),
        router,
        "satellite",
        "chatOrchestration.capabilities",
        &json!({"workspaceId":"task", "originChatId":"remote-chat", "chatAuthority":authority()}),
        None,
    )
    .await
    .unwrap();
    assert!(answer.get("caller").is_none());
}

#[tokio::test]
async fn routed_creation_preserves_lineage_origin_and_receipt_scope_without_hub_transcript() {
    let (_root, router, host, runtime, _service) = service_fixture().await;
    let metadata = json!({"parentChatId":"parent", "taskId":"task-1", "originKind":"delegation"});
    runtime
        .create(
            CreateChatInput {
                workspace_id: "task".into(),
                provider_instance_id: Some("codex".into()),
                metadata: Some(metadata.clone()),
                ..Default::default()
            },
            CallerCtx {
                scope: "chat:parent".into(),
                actor: "agent:parent".into(),
                mobile: false,
            },
            Some(ReceiptKey {
                verb: "delegate".into(),
                request_id: "once".into(),
                digest: "digest".into(),
            }),
        )
        .await
        .unwrap();
    runtime
        .send(
            "remote-chat",
            SendInput {
                client_message_id: "message".into(),
                text: "brief only".into(),
                attachments: vec![],
                delivery: "auto".into(),
                model: None,
                reasoning_effort: None,
                interaction_mode: None,
                runtime_mode_ceiling: None,
                origin: Some(json!({"kind":"chatMessage", "senderChatId":"parent"})),
            },
            CallerCtx::runtime(),
        )
        .await
        .unwrap();
    {
        let calls = host.calls.lock().unwrap();
        let created = &calls
            .iter()
            .find(|(_, _, payload)| payload["operation"] == "create")
            .unwrap()
            .2;
        assert_eq!(created["input"]["metadata"], metadata);
        assert_eq!(created["caller"]["scope"], "chat:parent");
        assert_eq!(created["receipt"]["request_id"], "once");
        let sent = &calls
            .iter()
            .find(|(_, _, payload)| {
                payload["operation"] == "command" && payload["op"].get("Send").is_some()
            })
            .unwrap()
            .2;
        assert_eq!(sent["op"]["Send"]["origin"]["senderChatId"], "parent");
    }
    assert!(router
        .store
        .agent_chat("remote-chat")
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn durable_remote_turns_are_available_beyond_the_live_snapshot_window() {
    let (_root, _router, _host, runtime, _service) = service_fixture().await;
    assert!(runtime.snapshot("remote-chat").await.unwrap()["turns"]
        .as_array()
        .unwrap()
        .is_empty());
    let turn = runtime
        .turn_for_client_message("remote-chat", "old-message")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(turn["turnId"], "old-turn");
    let durable = runtime
        .child_turn("remote-chat", "old-turn")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(durable.turn_status.as_deref(), Some("completed"));
    assert_eq!(
        durable.final_assistant_text.as_deref(),
        Some("durable old result")
    );
}

#[tokio::test]
async fn provider_catalog_can_target_an_explicit_remote_host_without_workspace() {
    let (_root, _router, host, runtime, _service) = service_fixture().await;
    let answer = runtime
        .providers_for_host(None, Some("satellite"), false)
        .await
        .unwrap();
    assert_eq!(answer["host"], "satellite");
    assert_eq!(host.calls.lock().unwrap().last().unwrap().0, "satellite");
    let wrong_owner = runtime
        .providers_for_host(Some("task"), Some("foreign"), false)
        .await
        .unwrap_err();
    assert_eq!(wrong_owner.wire_response(0)["errorCode"], "invalid_target");
}

#[test]
fn remote_tool_allowlist_is_exact() {
    assert!(is_chat_orchestration_verb("chatOrchestration.delegate"));
    assert!(!is_chat_orchestration_verb("chatOrchestration.futureAdmin"));
    assert!(!is_chat_orchestration_verb("agentChat.send"));
}

#[test]
fn forward_authority_comes_from_binding() {
    let binding = BoundChat {
        chat_id: "actual-chat".into(),
        generation: 9,
        runtime_mode: "auto".into(),
        credential_hash: "a".repeat(64),
        origin_host_id: None,
    };
    let stamped = forwarded_binding(&binding);
    assert_eq!(stamped["originChatId"], "actual-chat");
    assert_eq!(stamped["generation"], 9);
    assert!(stamped.get("runtimeMode").is_none());
    assert!(stamped.get("token").is_none());
}

struct PausedSatelliteTransport {
    runtime: AgentChatRuntime,
    arrived: tokio::sync::Notify,
    release: tokio::sync::Notify,
    received: std::sync::Mutex<Vec<Value>>,
}

#[async_trait]
impl super::super::agent_chat_remote::RemoteChatTransport for PausedSatelliteTransport {
    async fn request(&self, _workspace_id: &str, verb: &str, payload: Value) -> HostResult<Value> {
        assert_eq!(verb, INTERNAL_CHAT_REQUEST);
        self.received.lock().unwrap().push(payload.clone());
        if payload["op"].get("SendWithinCeiling").is_some() {
            self.arrived.notify_one();
            tokio::time::timeout(std::time::Duration::from_secs(5), self.release.notified())
                .await
                .expect("satellite command gate was not released before the fixture deadline");
        }
        handle_internal_runtime(&self.runtime, &payload).await
    }
}

#[tokio::test]
async fn a_remote_send_rechecks_the_carried_ceiling_after_concurrent_configuration() {
    use super::super::agent_chat_runtime::commands::ConfigureInput;
    use super::super::chat_orchestration::mock_provider::MockProviderFactory;

    let (_hub_root, mut router, _fake) = remote_fixture().await;
    let satellite_root = tempfile::tempdir().unwrap();
    let satellite_store = alera_core::runtime::RuntimeStore::open(satellite_root.path())
        .await
        .unwrap();
    let project = router.store.find_project("project").await.unwrap().unwrap();
    satellite_store.upsert_project(project).await.unwrap();
    let mut workspace = router.store.find_workspace("task").await.unwrap().unwrap();
    workspace.host_id = "local".into();
    satellite_store.upsert_workspace(workspace).await.unwrap();
    let factory = Arc::new(MockProviderFactory::default());
    let satellite = AgentChatRuntime::new(
        satellite_store.clone(),
        factory.clone(),
        Arc::new(satellite_store),
        Box::new(NullSink),
        Arc::new(InstanceDirectory::default()),
    );
    let created = satellite
        .create(
            CreateChatInput {
                workspace_id: "task".into(),
                provider_instance_id: Some("codex".into()),
                runtime_mode: Some("auto".into()),
                ..Default::default()
            },
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    let chat_id = created["chatId"].as_str().unwrap().to_owned();
    router.directory.remember(&chat_id, "task", "satellite");
    let transport = Arc::new(PausedSatelliteTransport {
        runtime: satellite.clone(),
        arrived: Default::default(),
        release: Default::default(),
        received: Default::default(),
    });
    router.transport = transport.clone();
    let hub_local = AgentChatRuntime::new(
        router.store.clone(),
        Arc::new(ProductionProviderFactory),
        Arc::new(router.store.clone()),
        Box::new(NullSink),
        Arc::new(InstanceDirectory::default()),
    );
    let runtime = RoutedChatRuntime::new(hub_local, router);
    assert_eq!(
        runtime.snapshot(&chat_id).await.unwrap()["session"]["runtimeMode"],
        "auto"
    );
    let sending = runtime.clone();
    let sending_chat = chat_id.clone();
    let send = tokio::spawn(async move {
        sending
            .command(
                &sending_chat,
                ChatOp::SendWithinCeiling {
                    input: SendInput {
                        client_message_id: "ceiling-race".into(),
                        text: "brief".into(),
                        attachments: vec![],
                        delivery: "auto".into(),
                        model: None,
                        reasoning_effort: None,
                        interaction_mode: None,
                        runtime_mode_ceiling: None,
                        origin: Some(json!({"kind":"chatMessage", "senderChatId":"parent"})),
                    },
                    runtime_mode_ceiling: "auto".into(),
                },
                CallerCtx {
                    scope: "chat:parent".into(),
                    actor: "agent:parent".into(),
                    mobile: false,
                },
                None,
            )
            .await
    });
    tokio::time::timeout(
        std::time::Duration::from_secs(5),
        transport.arrived.notified(),
    )
    .await
    .unwrap();
    satellite
        .command(
            &chat_id,
            ChatOp::Configure(ConfigureInput {
                runtime_mode: Some("full-access".into()),
                ..Default::default()
            }),
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    transport.release.notify_one();
    let error = tokio::time::timeout(std::time::Duration::from_secs(5), send)
        .await
        .unwrap()
        .unwrap()
        .unwrap_err();
    assert_eq!(error.wire_response(0)["errorCode"], "mode_ceiling");
    {
        let commands = transport.received.lock().unwrap();
        let carried = commands
            .iter()
            .find(|payload| payload["op"].get("SendWithinCeiling").is_some())
            .unwrap();
        assert_eq!(
            carried["op"]["SendWithinCeiling"]["runtime_mode_ceiling"],
            "auto"
        );
        assert!(!commands
            .iter()
            .any(|payload| payload["op"].get("Send").is_some()));
    }
    assert!(satellite.snapshot(&chat_id).await.unwrap()["turns"]
        .as_array()
        .unwrap()
        .is_empty());
    assert!(factory.launches.lock().unwrap().is_empty());
    satellite.shutdown().await;
}
