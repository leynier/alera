use super::*;

#[test]
fn fork_availability_survives_a_page_containing_only_the_active_turn() {
    let active = json!({"id":"active","status":"inProgress","items": (0..150).map(|i| json!({"type":"agentMessage","id":format!("message-{i}"),"text":format!("Message {i}")})).collect::<Vec<_>>()});
    for completed in [false, true] {
        let mut turns = Vec::new();
        if completed {
            turns.push(json!({"id":"finished","status":"completed","items":[]}));
        }
        turns.push(active.clone());
        let page =
            super::super::codex_state::latest_turn_page(&json!({"thread":{"turns":turns}}), 20)
                .unwrap();
        assert!(page.next_cursor.is_some());
        assert!(page.snapshot["timelineCells"]
            .as_array()
            .unwrap()
            .iter()
            .all(|cell| cell["turnId"] == "active"));
        assert_eq!(page.snapshot["hasCompletedTurns"], completed);
    }
}

#[tokio::test]
async fn completed_turn_availability_survives_live_eviction_and_resets_with_history() {
    let (_directory, mut actor, _backend, _rx) = fixture().await;
    let mut tab = actor.codex_tab("tab").await.unwrap();
    let previous = super::super::codex_state::snapshot(&tab);
    let completed = super::super::codex_state::append_message(
        &mut tab,
        json!({"method":"turn/completed","params":{"turnId":"third"}}),
    );
    let delta = super::super::codex_state::snapshot_delta(&previous, &completed, &[]);
    assert_eq!(delta["hasCompletedTurns"], true);
    super::super::codex_state::append_message(
        &mut tab,
        json!({"method":"turn/started","params":{"turnId":"active"}}),
    );
    for i in 0..250 {
        super::super::codex_state::append_message(
            &mut tab,
            json!({"method":"item/completed","params":{"turnId":"active","item":{"id":format!("message-{i}"),"type":"agentMessage","text":"Text"}}}),
        );
    }
    let current = super::super::codex_state::snapshot(&tab);
    assert_eq!(current["hasCompletedTurns"], true);
    assert!(current["timelineCells"]
        .as_array()
        .unwrap()
        .iter()
        .all(|cell| cell["turnId"] == "active"));
    actor.runtime_store.upsert_workspace_tab(tab).await.unwrap();
    actor
        .replace_codex_history_snapshot(
            &CodexChatDeliveryState::new("tab", "thread"),
            &json!({"thread":{"id":"thread","turns":[]}}),
        )
        .await
        .unwrap();
    let mut tab = actor.codex_tab("tab").await.unwrap();
    assert_eq!(tab.payload["codexSnapshot"]["hasCompletedTurns"], false);
    tab.payload["codexSnapshot"]["hasCompletedTurns"] = json!(true);
    super::super::codex_tab_lifecycle::clear_thread_identity(&mut tab);
    assert_eq!(tab.payload["codexSnapshot"]["hasCompletedTurns"], false);
}
