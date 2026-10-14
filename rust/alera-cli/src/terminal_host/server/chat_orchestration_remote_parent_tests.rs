use super::tests::service_fixture;
use super::*;

#[tokio::test]
async fn satellite_reverse_call_cannot_claim_human_parent_authority_from_payload_fields() {
    let (_root, router, host, _runtime, service) = service_fixture().await;
    for verb in ["delegate", "send"] {
        let payload = json!({"requestId":verb, "parentChatId":"remote-chat", "actor":"desktop", "scope":"desktop",
            "task":"brief", "target":{"workspace":{"workspaceId":"task"}},
            "chatId":"remote-chat", "message":"brief", "expectReply":true});
        let error = answer_remote_orchestration(
            Some(service.clone()),
            router.clone(),
            "satellite",
            &format!("chatOrchestration.{verb}"),
            &payload,
            None,
        )
        .await
        .unwrap_err();
        assert_eq!(error.wire_response(0)["errorCode"], "chat_scope_denied");
    }
    assert!(!host
        .calls
        .lock()
        .unwrap()
        .iter()
        .any(|(_, _, payload)| payload["operation"] == "create"));
}

#[tokio::test]
async fn remote_bound_agent_cannot_replace_its_parent_with_another_chat() {
    let (_root, router, _host, _runtime, service) = service_fixture().await;
    let authority =
        json!({"originChatId":"remote-chat", "generation":3, "credentialHash":"a".repeat(64)});
    let payload = json!({"requestId":"spoof-parent", "parentChatId":"unrelated-chat",
        "task":"brief", "target":{"workspace":{"workspaceId":"task"}}});
    let error = answer_remote_orchestration(
        Some(service),
        router,
        "satellite",
        "chatOrchestration.delegate",
        &payload,
        Some(&authority),
    )
    .await
    .unwrap_err();
    assert_eq!(error.wire_response(0)["errorCode"], "not_in_lineage");
}

#[tokio::test]
async fn human_parent_validation_uses_the_authoritative_remote_host_snapshot() {
    let (_root, _router, host, _runtime, service) = service_fixture().await;
    host.snapshot.lock().unwrap()["archived"] = json!(true);
    let caller = OrchestrationCaller::human(CallerCtx {
        scope: "mobile:phone".into(),
        actor: "mobile:phone".into(),
        mobile: true,
    });
    let payload = json!({"requestId":"archived", "parentChatId":"remote-chat", "task":"brief",
        "target":{"workspace":{"workspaceId":"task"}}});
    let error = service
        .handle("delegate", &payload, &caller)
        .await
        .unwrap_err();
    assert_eq!(error.wire_response(0)["errorCode"], "chat_archived");
    assert!(host
        .calls
        .lock()
        .unwrap()
        .iter()
        .any(|(workspace, verb, payload)| workspace == "task"
            && verb == INTERNAL_CHAT_REQUEST
            && payload["op"] == json!("Snapshot")));
}
