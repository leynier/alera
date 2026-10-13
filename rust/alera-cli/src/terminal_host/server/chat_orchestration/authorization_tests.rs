use alera_core::runtime::ChatOrchestrationTaskStatus as Status;
use serde_json::json;

use crate::terminal_host::server::agent_chat_runtime::commands::{ChatOp, ConfigureInput};
use crate::terminal_host::server::agent_chat_runtime::provider_factory::ProviderLaunchHook;

use super::delegation_tests::delegate_payload;
use super::test_support::{error_code, human, TestHarness, TEST_DEADLINE};

#[tokio::test]
async fn agent_reads_cross_project_chats_but_mutates_only_descendants() {
    let harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "auto").await;
    harness
        .send_human(&parent, "live-parent", "Perform orchestration.")
        .await;
    let caller = harness.agent(&parent).await;
    let unrelated = harness.create_chat("ws-b", "approval-required").await;
    assert_eq!(
        harness
            .service
            .handle("read", &json!({"chatId": unrelated}), &caller)
            .await
            .unwrap()["chat"]["chatId"],
        unrelated
    );
    let child_task = harness
        .service
        .handle(
            "delegate",
            &delegate_payload("descendant", json!({"workspace": {"workspaceId": "ws-b"}})),
            &caller,
        )
        .await
        .unwrap();
    let child = child_task["childChatId"].as_str().unwrap();
    let control = harness.control(child).await;
    tokio::time::timeout(TEST_DEADLINE, control.wait_turns(1))
        .await
        .unwrap();
    let unrelated_task = harness
        .service
        .handle(
            "delegate",
            &delegate_payload("unrelated-task", json!({"chat": {"chatId": unrelated}})),
            &human("desktop"),
        )
        .await
        .unwrap();
    for (verb, payload) in [
        (
            "interrupt",
            json!({"requestId": "deny-interrupt", "chatId": unrelated}),
        ),
        (
            "configure",
            json!({"requestId": "deny-configure", "chatId": unrelated, "model": "other"}),
        ),
        (
            "respond",
            json!({"requestId": "deny-respond", "chatId": unrelated,
            "runtimeRequestId": "forged", "response": {"type": "userInput", "answers": {}}}),
        ),
        (
            "cancel",
            json!({"requestId": "deny-cancel", "taskId": unrelated_task["taskId"]}),
        ),
    ] {
        let error = harness
            .service
            .handle(verb, &payload, &caller)
            .await
            .unwrap_err();
        assert_eq!(error_code(&error), "not_in_lineage", "{verb}");
    }
    harness
        .service
        .handle(
            "interrupt",
            &json!({"requestId": "own-child", "chatId": child}),
            &caller,
        )
        .await
        .unwrap();
    harness
        .task_status(child_task["taskId"].as_str().unwrap(), Status::Interrupted)
        .await;
    assert_eq!(control.interrupts.lock().unwrap().len(), 1);
    for scope in ["desktop", "mobile:phone"] {
        harness
            .service
            .handle(
                "interrupt",
                &json!({"requestId": format!("human-{scope}"),
            "chatId": unrelated}),
                &human(scope),
            )
            .await
            .unwrap();
    }
    harness.finish().await;
}

#[tokio::test]
async fn mode_ceiling_covers_new_chats_existing_chats_and_messages() {
    let harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "auto-accept-edits").await;
    harness
        .send_human(&parent, "parent", "Delegate at my mode.")
        .await;
    let caller = harness.agent(&parent).await;
    let elevated = harness.create_chat("ws-b", "full-access").await;
    let mut new_child = delegate_payload(
        "elevated-new",
        json!({"workspace": {"workspaceId": "ws-b"}}),
    );
    new_child["runtimeMode"] = json!("auto");
    for (verb, payload) in [
        ("delegate", new_child),
        (
            "delegate",
            delegate_payload("elevated-existing", json!({"chat": {"chatId": elevated}})),
        ),
        (
            "send",
            json!({"requestId": "elevated-send", "chatId": elevated, "message": "Do work."}),
        ),
    ] {
        let error = harness
            .service
            .handle(verb, &payload, &caller)
            .await
            .unwrap_err();
        assert_eq!(error_code(&error), "mode_ceiling", "{verb}");
    }
    let child = harness
        .service
        .handle(
            "delegate",
            &delegate_payload("inherited", json!({"workspace": {"workspaceId": "ws-b"}})),
            &caller,
        )
        .await
        .unwrap();
    assert_eq!(child["runtimeMode"], "auto-accept-edits");
    let capabilities = harness
        .service
        .handle("capabilities", &json!({}), &caller)
        .await
        .unwrap();
    assert_eq!(
        capabilities["ceilingRuntimeModes"],
        json!(["approval-required", "auto-accept-edits"])
    );
    for scope in ["desktop", "mobile:phone"] {
        let response = harness
            .service
            .handle(
                "send",
                &json!({"requestId": format!("human-{scope}"),
            "chatId": elevated, "message": "Human-authorized full-access work."}),
                &human(scope),
            )
            .await
            .unwrap();
        assert_eq!(response["chatId"], elevated);
    }
    harness.finish().await;
}

#[tokio::test]
async fn bound_connection_requires_a_live_turn_and_current_unarchived_generation() {
    let harness = TestHarness::new().await;
    let chat = harness.create_chat("ws-a", "approval-required").await;
    harness
        .send_human(&chat, "active", "Bind this live turn.")
        .await;
    let caller = harness.agent(&chat).await;
    let launch = harness
        .factory
        .launches
        .lock()
        .unwrap()
        .last()
        .unwrap()
        .clone();
    let path = std::path::PathBuf::from(&launch.env["ALERA_CHAT_CREDENTIAL_FILE"]);
    let token = std::fs::read_to_string(&path).unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        assert_eq!(
            std::fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );
        assert_eq!(
            std::fs::metadata(path.parent().unwrap())
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o700
        );
    }
    assert!(!serde_json::to_string(&launch.mcp_servers)
        .unwrap()
        .contains(&token));
    assert!(!harness
        .runtime
        .snapshot(&chat)
        .await
        .unwrap()
        .to_string()
        .contains(&token));
    let control = harness.control(&chat).await;
    control.complete(1, "Finished the live turn.");
    tokio::time::timeout(TEST_DEADLINE, async {
        loop {
            if harness.runtime.snapshot(&chat).await.unwrap()["session"]["activeTurnId"].is_null() {
                break;
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    let error = harness
        .service
        .handle("capabilities", &json!({}), &caller)
        .await
        .unwrap_err();
    assert_eq!(error_code(&error), "caller_turn_inactive");
    harness
        .runtime
        .command(
            &chat,
            ChatOp::Configure(ConfigureInput {
                provider_instance_id: Some("claudeAgent".into()),
                ..Default::default()
            }),
            human("desktop").ctx,
            None,
        )
        .await
        .unwrap();
    let invalid = harness.service.bind_credential(&token).await.unwrap_err();
    assert_eq!(error_code(&invalid), "chat_credential_invalid");
    let stale = harness
        .service
        .handle("capabilities", &json!({}), &caller)
        .await
        .unwrap_err();
    assert_eq!(error_code(&stale), "chat_credential_invalid");
    harness
        .runtime
        .command(&chat, ChatOp::Close, human("mobile:phone").ctx, None)
        .await
        .unwrap();
    assert_eq!(
        error_code(&harness.service.bind_credential(&token).await.unwrap_err()),
        "chat_credential_invalid"
    );
    harness.finish().await;
}

#[tokio::test]
async fn revoked_credentials_cannot_rebind_or_keep_an_existing_agent_connection_authorized() {
    let harness = TestHarness::new().await;
    let chat = harness.create_chat("ws-a", "approval-required").await;
    harness
        .send_human(
            &chat,
            "active",
            "Remain live while the credential is revoked.",
        )
        .await;
    let caller = harness.agent(&chat).await;
    let path = harness.factory.launches.lock().unwrap().last().unwrap().env
        ["ALERA_CHAT_CREDENTIAL_FILE"]
        .clone();
    let token = std::fs::read_to_string(&path).unwrap();
    harness
        .service
        .credential_hook()
        .revoke_chat(&chat, "closed")
        .await
        .unwrap();
    assert!(!std::path::Path::new(&path).exists());
    assert_eq!(
        error_code(&harness.service.bind_credential(&token).await.unwrap_err()),
        "chat_credential_invalid"
    );
    let error = harness
        .service
        .handle("read", &json!({"chatId": chat}), &caller)
        .await
        .unwrap_err();
    assert_eq!(error_code(&error), "chat_credential_invalid");
    harness.finish().await;
}

#[tokio::test]
async fn same_generation_credential_replacement_invalidates_the_previous_connection() {
    let harness = TestHarness::new().await;
    let chat = harness.create_chat("ws-a", "approval-required").await;
    harness
        .send_human(
            &chat,
            "active",
            "Remain live across a credential replacement.",
        )
        .await;
    let caller = harness.agent(&chat).await;
    let mut launch = harness
        .factory
        .launches
        .lock()
        .unwrap()
        .last()
        .unwrap()
        .clone();
    let old_path = launch.env["ALERA_CHAT_CREDENTIAL_FILE"].clone();
    let old_token = std::fs::read_to_string(&old_path).unwrap();
    launch.mcp_servers.clear();
    harness
        .service
        .credential_hook()
        .prepare(&mut launch)
        .await
        .unwrap();
    assert!(!std::path::Path::new(&old_path).exists());
    let new_token = std::fs::read_to_string(&launch.env["ALERA_CHAT_CREDENTIAL_FILE"]).unwrap();
    assert!(new_token != old_token);
    assert_eq!(
        harness
            .service
            .bind_credential(&new_token)
            .await
            .unwrap()
            .generation,
        caller.bound.as_ref().unwrap().generation
    );
    assert_eq!(
        error_code(
            &harness
                .service
                .bind_credential(&old_token)
                .await
                .unwrap_err()
        ),
        "chat_credential_invalid"
    );
    assert_eq!(
        error_code(
            &harness
                .service
                .handle("capabilities", &json!({}), &caller)
                .await
                .unwrap_err()
        ),
        "chat_credential_invalid"
    );
    harness.finish().await;
}

#[tokio::test]
async fn archiving_a_still_live_chat_invalidates_its_bound_connection() {
    let harness = TestHarness::new().await;
    let chat = harness.create_chat("ws-a", "approval-required").await;
    harness
        .send_human(&chat, "active", "Remain live when archival is persisted.")
        .await;
    let caller = harness.agent(&chat).await;
    let path = harness.factory.launches.lock().unwrap().last().unwrap().env
        ["ALERA_CHAT_CREDENTIAL_FILE"]
        .clone();
    let token = std::fs::read_to_string(path).unwrap();
    harness.store.archive_agent_chat(&chat).await.unwrap();
    let error = harness
        .service
        .handle("read", &json!({"chatId": chat}), &caller)
        .await
        .unwrap_err();
    assert_eq!(error_code(&error), "chat_credential_invalid");
    assert_eq!(
        error_code(&harness.service.bind_credential(&token).await.unwrap_err()),
        "chat_credential_invalid"
    );
    harness.finish().await;
}
