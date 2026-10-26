use std::collections::{BTreeMap, BTreeSet};

use serde_json::{json, Value};

use super::agent_chat_test_support::*;
use super::*;

fn turn(n: usize, status: &str) -> Value {
    json!({
        "turnId": format!("t{n:04}"), "status": status,
        "provider": "codex", "providerInstanceId": "codex-default",
        "generation": 1, "model": null,
        "startedAt": "2026-10-12T10:00:00.000Z",
        "completedAt": "2026-10-12T10:00:01.000Z",
        "reason": "fixture", "errorMessage": "retained",
        "futureMetadata": {"text": "m".repeat(1024)},
    })
}

fn turn_item(n: usize) -> Value {
    let mut value = item(&format!("i{n:04}"), "assistant_message", "Hello 😀");
    value["turnId"] = json!(format!("t{n:04}"));
    value
}

#[tokio::test]
async fn more_than_1500_turn_commits_keep_full_history_and_bounded_views() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = create_chat(&store, "ws", "tab").await;
    let mut next = snapshot(&chat_id, "ws", "tab", 0);
    for n in 0..1505 {
        next["cursor"] = json!(n + 1);
        next["turns"] = json!([turn(n, "completed")]);
        let outcome = store
            .commit_agent_chat(
                &chat_id,
                n as i64,
                &next,
                &json!({"turns": [turn(n, "completed")], "items": [turn_item(n)]}),
                None,
            )
            .await
            .unwrap();
        assert!(matches!(outcome, AgentChatCommitOutcome::Committed(_)));
    }
    let chat = store.agent_chat(&chat_id).await.unwrap().unwrap();
    assert_eq!(chat.cursor, 1505);
    assert!(serde_json::to_string(&chat.snapshot).unwrap().len() < 1024 * 1024);
    assert!(chat.snapshot["turns"].as_array().unwrap().len() <= 232);
    assert!(!chat.snapshot["turns"]
        .as_array()
        .unwrap()
        .contains(&turn(0, "completed")));
    assert_eq!(
        store.agent_chat_turn(&chat_id, "t0000").await.unwrap(),
        Some(turn(0, "completed"))
    );
    let header: String =
        sqlx::query_scalar("SELECT snapshotJson FROM agentChatSessions WHERE chatId = ?")
            .bind(&chat_id)
            .fetch_one(store.pool())
            .await
            .unwrap();
    assert!(header.len() < 2048);
    assert!(serde_json::from_str::<Value>(&header)
        .unwrap()
        .get("turns")
        .is_none());

    let mut before = Some(i64::MAX);
    let mut seen = BTreeSet::new();
    while let Some(cursor) = before {
        let page = store
            .agent_chat_history(&chat_id, cursor, 200)
            .await
            .unwrap();
        let turns: BTreeMap<_, _> = page
            .turns
            .iter()
            .map(|turn| (turn["turnId"].as_str().unwrap(), turn))
            .collect();
        for value in &page.items {
            let id = value["turnId"].as_str().unwrap();
            assert!(seen.insert(id.to_string()));
            let n: usize = id[1..].parse().unwrap();
            assert_eq!(*turns[id], turn(n, "completed"));
        }
        assert!(serde_json::to_string(&page).unwrap().len() < 320 * 1024);
        before = page.history_before;
    }
    assert_eq!(seen.len(), 1505);
    sqlx::query("DELETE FROM agentChatEvents WHERE chatId = ? AND cursor <= 1490")
        .bind(&chat_id)
        .execute(store.pool())
        .await
        .unwrap();
    assert!(
        store
            .agent_chat_events(&chat_id, 0, 200)
            .await
            .unwrap()
            .snapshot_required
    );
    assert_eq!(
        store.agent_chat_turn(&chat_id, "t0000").await.unwrap(),
        Some(turn(0, "completed"))
    );
    store.reset_orchestration_tasks().await.unwrap();
    store.reset_orchestration_messages().await.unwrap();
    store.archive_agent_chat(&chat_id).await.unwrap();
    assert_eq!(
        store.agent_chat_turn(&chat_id, "t0000").await.unwrap(),
        Some(turn(0, "completed"))
    );
    store
        .restore_agent_chat(&chat_id, &tab(&chat_id, "ws", "restored"))
        .await
        .unwrap();
    let (cursor, mut switched) = next_snapshot(&store, &chat_id).await;
    switched["provider"] = json!("claude");
    switched["providerInstanceId"] = json!("claude-default");
    switched["session"].as_object_mut().unwrap().remove("model");
    store.commit_agent_chat(&chat_id, cursor, &switched,
        &json!({"provider": "claude", "providerInstanceId": "claude-default", "session": switched["session"]}), None)
        .await.unwrap();
    assert_eq!(
        store
            .agent_chat(&chat_id)
            .await
            .unwrap()
            .unwrap()
            .generation,
        2
    );
    assert!(store
        .find_workspace_tab("restored")
        .await
        .unwrap()
        .unwrap()
        .payload
        .get("model")
        .is_none());
    assert_eq!(
        store.agent_chat_turn(&chat_id, "t0000").await.unwrap(),
        Some(turn(0, "completed"))
    );
    store.remove_workspace("ws", true).await.unwrap();
    assert!(store
        .agent_chat_turn(&chat_id, "t0000")
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn old_active_and_pending_turns_are_projected_and_recovered() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = new_chat_id();
    let mut initial = snapshot(&chat_id, "ws", "tab", 0);
    let mut active = turn(0, "running");
    active.as_object_mut().unwrap().remove("completedAt");
    initial["turns"] = json!((0..300)
        .map(|n| if n == 0 {
            active.clone()
        } else {
            turn(n, "completed")
        })
        .collect::<Vec<_>>());
    initial["items"] = json!((0..300).map(turn_item).collect::<Vec<_>>());
    initial["items"][0]["clientMessageId"] = json!("old-client-message");
    initial["session"]["activeTurnId"] = json!("t0000");
    initial["session"]["status"] = json!("running");
    initial["pendingRequests"] = json!([{"requestId": "q", "kind": "approval", "turnId": "t0001"}]);
    store
        .create_agent_chat(
            &record(&chat_id, "ws", "tab", initial),
            &tab(&chat_id, "ws", "tab"),
            None,
        )
        .await
        .unwrap();
    let view = store.agent_chat(&chat_id).await.unwrap().unwrap().snapshot;
    let turns = view["turns"].as_array().unwrap();
    assert!(turns.contains(&active));
    assert!(turns.contains(&turn(1, "completed")));
    assert_eq!(
        store
            .agent_chat_turn_for_client_message(&chat_id, "old-client-message")
            .await
            .unwrap(),
        Some(active.clone())
    );
    assert!(store
        .agent_chat_turn_for_client_message(&chat_id, "not-sent")
        .await
        .unwrap()
        .is_none());
    assert!(!view["items"].as_array().unwrap().contains(&turn_item(0)));
    let outcomes = store.recover_agent_chats().await.unwrap();
    assert_eq!(outcomes[0].interrupted_turn_ids, ["t0000"]);
    let recovered = store
        .agent_chat_turn(&chat_id, "t0000")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(recovered["status"], "interrupted");
    assert_eq!(recovered["reason"], "runtimeRestarted");
    assert_eq!(recovered["futureMetadata"], active["futureMetadata"]);
    assert!(store.recover_agent_chats().await.unwrap().is_empty());
}

#[tokio::test]
async fn old_turn_upserts_and_utf16_appends_replay_without_projection_removals() {
    let (_dir, store) = store_with_workspace("ws").await;
    let chat_id = new_chat_id();
    let mut initial = snapshot(&chat_id, "ws", "tab", 0);
    initial["turns"] = json!((0..300).map(|n| turn(n, "completed")).collect::<Vec<_>>());
    initial["items"] = json!((0..300).map(turn_item).collect::<Vec<_>>());
    store
        .create_agent_chat(
            &record(&chat_id, "ws", "tab", initial),
            &tab(&chat_id, "ws", "tab"),
            None,
        )
        .await
        .unwrap();
    let page = store.agent_chat_history(&chat_id, 2, 1).await.unwrap();
    assert_eq!(page.turns, [turn(0, "completed")]);
    let (cursor, next) = next_snapshot(&store, &chat_id).await;
    assert!(!next["turns"]
        .as_array()
        .unwrap()
        .contains(&turn(0, "completed")));
    let mut changed = turn(0, "failed");
    changed["errorMessage"] = json!("late failure");
    let delta = json!({"turns": [changed], "textAppends": [{"itemId": "i0000", "stream": "text", "offset": 8, "text": " done"}]});
    store
        .commit_agent_chat(&chat_id, cursor, &next, &delta, None)
        .await
        .unwrap();
    let events = store.agent_chat_events(&chat_id, 0, 10).await.unwrap();
    assert_eq!(events.events[0].delta, delta);
    let mut loaded_item = page.items[0].clone();
    let loaded_turn = events.events[0].delta["turns"][0].clone();
    loaded_item["text"] = json!(format!(
        "{}{}",
        loaded_item["text"].as_str().unwrap(),
        events.events[0].delta["textAppends"][0]["text"]
            .as_str()
            .unwrap()
    ));
    assert_eq!(
        Some(loaded_turn),
        store.agent_chat_turn(&chat_id, "t0000").await.unwrap()
    );
    assert_eq!(
        Some(loaded_item),
        store.agent_chat_item(&chat_id, "i0000").await.unwrap()
    );
    let (cursor, mut invalid) = next_snapshot(&store, &chat_id).await;
    invalid["turns"] = json!([turn(0, "completed")]);
    assert!(store
        .commit_agent_chat(&chat_id, cursor, &invalid, &json!({}), None)
        .await
        .is_err());
    assert_eq!(store.agent_chat(&chat_id).await.unwrap().unwrap().cursor, 1);
}

#[tokio::test]
async fn orchestration_recovers_a_completed_child_turn_outside_its_snapshot() {
    let (_dir, store) = store_with_workspace("ws").await;
    let parent = create_chat(&store, "ws", "parent").await;
    let child = new_chat_id();
    let mut initial = snapshot(&child, "ws", "child", 0);
    initial["turns"] = json!((0..300).map(|n| turn(n, "completed")).collect::<Vec<_>>());
    initial["items"] = json!((0..300).map(turn_item).collect::<Vec<_>>());
    store
        .create_agent_chat(
            &record(&child, "ws", "child", initial),
            &tab(&child, "ws", "child"),
            None,
        )
        .await
        .unwrap();
    let view = store.agent_chat(&child).await.unwrap().unwrap().snapshot;
    assert!(!view["turns"]
        .as_array()
        .unwrap()
        .contains(&turn(0, "completed")));
    let input = NewChatOrchestrationTask {
        task_id: "old-turn-task".into(),
        kind: ChatOrchestrationTaskKind::Delegate,
        caller_scope: "desktop".into(),
        parent_task_id: None,
        parent_chat_id: Some(parent),
        child_chat_id: Some(child.clone()),
        project_id: None,
        workspace_id: Some("ws".into()),
        host_id: None,
        target: ChatOrchestrationTarget::Chat {
            chat_id: child.clone(),
        },
        title: None,
        role: None,
        brief: "Check the old turn".into(),
        notify: ChatOrchestrationNotify::Never,
        launch_options: None,
    };
    let ChatOrchestrationCreateOutcome::Created(task) = store
        .create_chat_orchestration_task(input, None)
        .await
        .unwrap()
    else {
        panic!("task was not created");
    };
    let task = *task;
    let mut running = ChatOrchestrationTaskTransition::new(
        [ChatOrchestrationTaskStatus::Preparing],
        ChatOrchestrationTaskStatus::Running,
    );
    running.expected_revision = Some(task.revision);
    running.child_turn_id = Some("t0000".into());
    store
        .transition_chat_orchestration_task(&task.task_id, &running)
        .await
        .unwrap();
    let child_turn = store
        .chat_orchestration_child_turn(&child, "t0000")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(child_turn.turn_status.as_deref(), Some("completed"));
    assert_eq!(child_turn.final_assistant_text.as_deref(), Some("Hello 😀"));
    let recovered = store.recover_chat_orchestration().await.unwrap();
    assert_eq!(recovered.settled.len(), 1);
    assert_eq!(
        recovered.settled[0].status,
        ChatOrchestrationTaskStatus::Completed
    );
    assert_eq!(
        recovered.settled[0].result_text.as_deref(),
        Some("Hello 😀")
    );
}
