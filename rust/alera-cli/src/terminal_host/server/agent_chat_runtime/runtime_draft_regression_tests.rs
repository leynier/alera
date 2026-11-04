use super::*;

#[tokio::test]
async fn restarted_never_sent_chat_stays_ready_without_recovery_or_provider() {
    let harness = TestHarness::new().await;
    let chat_id = harness.create_chat("ws-a", "approval-required").await;
    harness.runtime.shutdown().await;
    assert!(harness
        .runtime
        .recover_after_restart()
        .await
        .unwrap()
        .is_empty());
    let snapshot = harness.runtime.snapshot(&chat_id).await.unwrap();
    assert_eq!(snapshot["session"]["status"], "stopped");
    assert!(snapshot["recovery"].is_null());
    assert!(snapshot["turns"].as_array().unwrap().is_empty());
    assert!(snapshot["items"].as_array().unwrap().is_empty());
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    harness
        .runtime
        .command(
            &chat_id,
            ChatOp::Recover { mode: None },
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    assert!(harness.factory.launches.lock().unwrap().is_empty());
    harness.finish().await;
}

#[tokio::test]
async fn legacy_title_source_migration_explains_its_delta_and_keeps_manual_title() {
    let harness = TestHarness::new().await;
    let default_chat = harness.create_chat("ws-a", "approval-required").await;
    let renamed_chat = harness.create_chat("ws-a", "approval-required").await;
    harness
        .runtime
        .command(
            &renamed_chat,
            ChatOp::Rename {
                title: "Existing manual title".into(),
            },
            CallerCtx::runtime(),
            None,
        )
        .await
        .unwrap();
    harness.runtime.shutdown().await;
    sqlx::query("UPDATE agentChatSessions SET snapshotJson = json_remove(snapshotJson, '$.titleSource') WHERE chatId IN (?, ?)")
        .bind(&default_chat).bind(&renamed_chat).execute(harness.store.pool()).await.unwrap();
    let default_snapshot = harness.runtime.snapshot(&default_chat).await.unwrap();
    assert_eq!(default_snapshot["titleSource"], "default");
    let renamed_snapshot = harness.runtime.snapshot(&renamed_chat).await.unwrap();
    assert_eq!(renamed_snapshot["titleSource"], "user");
    harness
        .send_human(&renamed_chat, "first", "New prompt title")
        .await;
    assert_eq!(
        harness.runtime.snapshot(&renamed_chat).await.unwrap()["title"],
        "Existing manual title"
    );
    harness
        .send_human(&default_chat, "first", "Derived prompt title")
        .await;
    assert_eq!(
        harness.runtime.snapshot(&default_chat).await.unwrap()["title"],
        "Derived prompt title"
    );
    harness.finish().await;
}
