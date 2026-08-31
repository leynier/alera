use super::{complete_edit, fixture};
use serde_json::json;

#[tokio::test]
async fn rollback_receipt_persistence_failure_stays_locked_until_reconciliation() {
    for failed_phase in ["rollingBack", "rolledBack"] {
        let (_directory, mut actor, backend, mut rx) = fixture().await;
        let before = actor.codex_tab("tab").await.unwrap().payload;
        sqlx::query(sqlx::AssertSqlSafe(format!(
            "CREATE TRIGGER fail_rollback_save BEFORE UPDATE ON codexChatState WHEN json_extract(NEW.stateJson, '$.operations[0].phase') = '{failed_phase}' BEGIN SELECT RAISE(FAIL, 'simulated receipt persistence failure'); END"
        )))
        .execute(actor.runtime_store.pool()).await.unwrap();
        actor.edit_codex_history(&json!({
            "tabId":"tab","expectedThreadId":"thread","operationId":"edit",
            "turnId":"second","itemId":"user-second","text":"Correction","expectedHistoryRevision":0,
        })).await.unwrap();
        let state = complete_edit(&mut actor, &mut rx).await;
        assert!(state.paused);
        assert_eq!(state.history_revision, 0);
        assert_eq!(actor.codex_tab("tab").await.unwrap().payload, before);
        assert!(!backend
            .lock()
            .unwrap()
            .calls
            .iter()
            .any(|(method, _)| method == "turn/start"));
        if failed_phase == "rollingBack" {
            assert_eq!(state.operations[0].phase, "failed");
            assert!(!state.history_locked());
            assert_eq!(backend.lock().unwrap().turns.len(), 3);
            assert!(!backend
                .lock()
                .unwrap()
                .calls
                .iter()
                .any(|(method, _)| method == "thread/rollback"));
            continue;
        }

        assert_eq!(backend.lock().unwrap().turns.len(), 1);
        assert_eq!(state.operations[0].phase, "uncertain");
        assert_eq!(state.operations[0].payload["uncertainPhase"], "rollingBack");
        assert!(state.history_locked());
        assert!(actor
            .edit_codex_history(&json!({
                "tabId":"tab","expectedThreadId":"thread","operationId":"another-edit",
                "turnId":"first","text":"Another correction","expectedHistoryRevision":0,
            }))
            .await
            .is_err());
        assert!(actor.handle_codex_queue_request("codex.queue.resume", &json!({
            "tabId":"tab","expectedThreadId":"thread","expectedRevision":state.revision,"operationId":"resume",
        })).await.is_err());

        sqlx::query("DROP TRIGGER fail_rollback_save")
            .execute(actor.runtime_store.pool())
            .await
            .unwrap();
        actor
            .reconcile_codex_history_edit("tab", "edit")
            .await
            .unwrap();
        let reconciled = actor
            .runtime_store
            .codex_chat_state("thread")
            .await
            .unwrap()
            .unwrap();
        assert_eq!(reconciled.operations[0].phase, "rolledBack");
        assert!(reconciled.paused);
        assert!(reconciled.history_locked());
        assert_eq!(reconciled.history_revision, 1);
        assert_eq!(reconciled.discarded_turn_ids, ["second", "third"]);
        let tab = actor.codex_tab("tab").await.unwrap();
        assert_eq!(tab.payload["codexHistoryRevision"], 1);
        assert!(tab.payload["codexSnapshot"]["activeTurnId"].is_null());
        assert!(!backend
            .lock()
            .unwrap()
            .calls
            .iter()
            .any(|(method, _)| method == "turn/start"));

        actor
            .edit_codex_history(
                &json!({"tabId":"tab","expectedThreadId":"thread","operationId":"edit"}),
            )
            .await
            .unwrap();
        let completed = complete_edit(&mut actor, &mut rx).await;
        assert_eq!(completed.operations[0].phase, "completed");
        assert!(completed.paused);
        let calls = &backend.lock().unwrap().calls;
        assert_eq!(
            calls
                .iter()
                .filter(|(method, _)| method == "thread/rollback")
                .count(),
            1
        );
        let sends: Vec<_> = calls
            .iter()
            .filter(|(method, _)| method == "turn/start")
            .collect();
        assert_eq!(sends.len(), 1);
        assert_eq!(sends[0].1["input"][0]["text"], "Correction");
    }
}
