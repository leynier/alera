use super::*;
use alera_core::runtime::WorkspaceTabRecord;

#[derive(Default)]
pub(crate) struct FakeChatHost {
    pub(crate) calls: Mutex<Vec<(String, String, Value)>>,
    pub(crate) summaries: Mutex<Vec<Value>>,
    pub(crate) tabs: Mutex<Vec<WorkspaceTabRecord>>,
    pub(crate) snapshot: Mutex<Value>,
    pub(crate) credential: Mutex<Option<(String, i64, String)>>,
    pub(crate) unavailable: Mutex<bool>,
}

#[async_trait]
impl RemoteChatTransport for FakeChatHost {
    async fn request(&self, workspace_id: &str, verb: &str, payload: Value) -> HostResult<Value> {
        self.calls
            .lock()
            .unwrap()
            .push((workspace_id.into(), verb.into(), payload.clone()));
        if *self.unavailable.lock().unwrap() {
            return Err(HostError::conflict(
                "host_unavailable",
                "The fake host is offline.",
                json!({}),
            ));
        }
        match verb {
            "agentChat.list" => Ok(json!({"chats": self.summaries.lock().unwrap().clone()})),
            "tab.list" => Ok(json!(self.tabs.lock().unwrap().clone())),
            INTERNAL_CHAT_REQUEST => match payload["operation"].as_str() {
                Some("summaries") => Ok(json!({"chats": self.summaries.lock().unwrap().clone()})),
                Some("wire") | Some("create") => {
                    let snapshot = self.snapshot.lock().unwrap().clone();
                    Ok(
                        json!({"chatId":snapshot["chatId"], "tabId":snapshot["tabId"], "snapshot":snapshot}),
                    )
                }
                Some("command") => Ok(self.snapshot.lock().unwrap().clone()),
                Some("validateBinding") => {
                    let binding = self.credential.lock().unwrap().clone();
                    if binding.as_ref().is_none_or(|(chat, generation, hash)| {
                        payload["chatId"] != *chat
                            || payload["generation"] != *generation
                            || payload["credentialHash"] != *hash
                    }) {
                        return Err(HostError::conflict(
                            "chat_credential_invalid",
                            "The fake credential was revoked.",
                            json!({}),
                        ));
                    }
                    Ok(self.snapshot.lock().unwrap().clone())
                }
                Some("turnForClientMessage") => {
                    Ok(json!({"turnId":"old-turn", "status":"completed"}))
                }
                Some("childTurn") => {
                    Ok(json!({"turnStatus":"completed", "finalAssistantText":"durable old result"}))
                }
                _ => Err(HostError::format("Unknown fake operation")),
            },
            "agentChat.providers" => Ok(json!({"providers":[], "host":"satellite"})),
            _ => Err(HostError::format("Unknown fake verb")),
        }
    }

    async fn request_host(&self, host_id: &str, verb: &str, payload: Value) -> HostResult<Value> {
        self.request(host_id, verb, payload).await
    }
}

pub(crate) async fn remote_fixture() -> (tempfile::TempDir, RemoteChatRouter, Arc<FakeChatHost>) {
    let (root, actor) = super::super::checkout_buffer_guards_tests::fixture().await;
    let mut workspace = actor
        .runtime_store
        .find_workspace("task")
        .await
        .unwrap()
        .unwrap();
    workspace.host_id = "satellite".into();
    actor
        .runtime_store
        .upsert_workspace(workspace)
        .await
        .unwrap();
    let host = Arc::new(FakeChatHost::default());
    let tab = super::super::agent_chat_runtime::tab_directory::chat_tab_record(
        "remote-tab",
        "task",
        "Remote Chat",
        json!({"chatId":"remote-chat", "provider":"codex", "providerInstanceId":"codex"}),
    );
    *host.tabs.lock().unwrap() = vec![tab];
    *host.summaries.lock().unwrap() = vec![
        json!({"chatId":"remote-chat", "workspaceId":"task", "tabId":"remote-tab", "title":"Remote Chat", "provider":"codex", "providerInstanceId":"codex", "archived":false, "cursor":4}),
    ];
    *host.snapshot.lock().unwrap() = json!({"chatId":"remote-chat", "workspaceId":"task", "tabId":"remote-tab", "archived":false, "cursor":4, "session":{"generation":3,"runtimeMode":"auto","status":"running","activeTurnId":"turn"},"turns":[],"items":[]});
    *host.credential.lock().unwrap() = Some(("remote-chat".into(), 3, "a".repeat(64)));
    let router = RemoteChatRouter {
        store: actor.runtime_store.clone(),
        directory: RemoteChatDirectory::default(),
        transport: host.clone(),
    };
    (root, router, host)
}

#[tokio::test]
async fn archived_chat_id_reopens_on_owner_without_workspace_payload() {
    let (_root, router, host) = remote_fixture().await;
    host.summaries.lock().unwrap()[0]["archived"] = json!(true);
    host.summaries.lock().unwrap()[0]["tabId"] = Value::Null;
    host.tabs.lock().unwrap().clear();
    let caller = CallerCtx {
        scope: "mobile:phone".into(),
        actor: "mobile:phone".into(),
        mobile: true,
    };
    let answer = router
        .forward_wire(
            "agentChat.reopen",
            &json!({"chatId":"remote-chat","requestId":"reopen"}),
            caller.clone(),
        )
        .await
        .unwrap()
        .unwrap();
    assert_eq!(answer["chatId"], "remote-chat");
    {
        let calls = host.calls.lock().unwrap();
        let forwarded = calls
            .iter()
            .find(|(_, verb, payload)| {
                verb == INTERNAL_CHAT_REQUEST && payload["operation"] == "wire"
            })
            .unwrap();
        assert_eq!(forwarded.0, "task");
        assert_eq!(forwarded.2["caller"], json!(caller));
        assert!(forwarded.2["payload"].get("workspaceId").is_none());
        assert!(calls
            .iter()
            .any(|(_, verb, payload)| verb == INTERNAL_CHAT_REQUEST
                && payload["operation"] == "summaries"
                && payload["includeArchived"] == true));
    }
    assert!(router
        .store
        .agent_chat("remote-chat")
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn mirror_keeps_local_tabs_and_rejects_foreign_workspace_and_id_collisions() {
    let (_root, router, host) = remote_fixture().await;
    let mut foreign = host.tabs.lock().unwrap()[0].clone();
    foreign.id = "foreign".into();
    foreign.workspace_id = "sibling".into();
    let mut collision = host.tabs.lock().unwrap()[0].clone();
    collision.id = "task-editor".into();
    host.tabs.lock().unwrap().extend([foreign, collision]);
    router.sync_workspace("task").await.unwrap();
    assert!(router
        .store
        .find_workspace_tab("remote-tab")
        .await
        .unwrap()
        .is_some());
    assert!(router
        .store
        .find_workspace_tab("foreign")
        .await
        .unwrap()
        .is_none());
    assert_eq!(
        router
            .store
            .find_workspace_tab("task-editor")
            .await
            .unwrap()
            .unwrap()
            .kind,
        "editor"
    );
    host.tabs.lock().unwrap().clear();
    router.sync_workspace("task").await.unwrap();
    assert!(router
        .store
        .find_workspace_tab("remote-tab")
        .await
        .unwrap()
        .is_none());
    assert!(router
        .store
        .find_workspace_tab("task-editor")
        .await
        .unwrap()
        .is_some());
    assert!(router
        .store
        .agent_chat("remote-chat")
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn relay_requires_owner_and_known_chat_and_ignores_stale_cursor() {
    let (_root, router, _host) = remote_fixture().await;
    let payload = json!({"chatId":"remote-chat", "workspaceId":"task", "cursor":5, "delta":{"textAppends":[{"text":"private transcript"}]}});
    assert!(router
        .validated_change("foreign-host", &payload)
        .await
        .unwrap()
        .is_none());
    let mut foreign = payload.clone();
    foreign["chatId"] = json!("foreign-chat");
    assert!(router
        .validated_change("satellite", &foreign)
        .await
        .unwrap()
        .is_none());
    let change = router
        .validated_change("satellite", &payload)
        .await
        .unwrap()
        .unwrap();
    let mut subscription = router.directory.subscribe();
    router.directory.publish(change.clone());
    assert_eq!(subscription.recv().await.unwrap(), change);
    assert!(router
        .validated_change("satellite", &payload)
        .await
        .unwrap()
        .is_none());
    assert!(router
        .store
        .agent_chat("remote-chat")
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn deletion_relay_rejects_foreign_chat_host_and_missing_discard_state() {
    let (_root, router, _host) = remote_fixture().await;
    router.list_remote("task", true).await.unwrap();
    let payload = json!({"chatId":"remote-chat","workspaceId":"task","discarded":true});
    assert!(router
        .validated_deletion("foreign-host", &payload)
        .await
        .unwrap()
        .is_none());
    let mut unknown = payload.clone();
    unknown["chatId"] = json!("other-chat");
    assert!(router
        .validated_deletion("satellite", &unknown)
        .await
        .unwrap()
        .is_none());
    let mut malformed = payload.clone();
    malformed.as_object_mut().unwrap().remove("discarded");
    assert!(router
        .validated_deletion("satellite", &malformed)
        .await
        .unwrap()
        .is_none());
    assert_eq!(
        router
            .validated_deletion("satellite", &payload)
            .await
            .unwrap(),
        Some(ChatRuntimeEvent::Deleted {
            chat_id: "remote-chat".into(),
            workspace_id: "task".into(),
            discarded: true
        })
    );
}

#[tokio::test]
async fn an_offline_owner_is_distinct_from_an_unknown_chat() {
    let (_root, router, host) = remote_fixture().await;
    *host.unavailable.lock().unwrap() = true;
    let error = router.chat_workspace("remote-chat").await.unwrap_err();
    assert_eq!(error.wire_response(0)["errorCode"], "host_unavailable");
    *host.unavailable.lock().unwrap() = false;
    assert!(router
        .chat_workspace("missing-chat")
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn ordinary_clients_cannot_use_the_internal_runtime_seam() {
    let (_root, mut actor) = super::super::checkout_buffer_guards_tests::fixture().await;
    let error = actor.try_start_agent_chat_remote_request(3, 7, INTERNAL_CHAT_REQUEST, &json!({"operation":"command", "chatId":"remote-chat", "caller":{"scope":"runtime","actor":"runtime","mobile":false}, "op":"Snapshot"})).await.unwrap_err();
    assert_eq!(error.wire_response(0)["errorCode"], "chat_scope_denied");
}
