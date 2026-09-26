use super::*;
use crate::runtime::{OrchestrationBoardBucket, OrchestrationBoardQuery};

#[tokio::test]
async fn cleanup_catalog_pages_and_board_attention_survive_closed_runs() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    sqlx::query("INSERT INTO orchestrationCoordinatorRuns(id,spec,status,workspace_id,execution_policy_status,created_at)
        VALUES('run','Finished workflow','completed','owner','none','2026-09-12 12:00:00')")
        .execute(store.pool()).await.unwrap();
    for number in 1..=30_u128 {
        sqlx::query("INSERT INTO workflowCleanup(id,run_id,digest,document,expires_at,state) VALUES(?,'run','digest','{\"items\":[{},{}]}',0,'preview')")
            .bind(uuid::Uuid::from_u128(number).to_string()).execute(store.pool()).await.unwrap();
    }
    let query = WorkflowCleanupQuery {
        run_id: "run".into(),
        before_row: None,
    };
    let first = store.workflow_cleanups(&query).await.unwrap();
    assert_eq!(first.run_id, "run");
    assert_eq!(first.items.len(), 25);
    assert_eq!(first.items[0].id, uuid::Uuid::from_u128(30).to_string());
    assert!(first
        .items
        .iter()
        .all(|item| item.resource_count == 2 && item.retired_count == 0));
    let second = store
        .workflow_cleanups(&WorkflowCleanupQuery {
            run_id: "run".into(),
            before_row: first.next_before_row,
        })
        .await
        .unwrap();
    assert_eq!(second.items.len(), 5);
    assert!(second.next_before_row.is_none());
    assert_eq!(second.revision, first.revision);
    let before = store
        .orchestration_board_snapshot(&OrchestrationBoardQuery::default())
        .await
        .unwrap();
    assert_eq!(before.items[0].bucket, OrchestrationBoardBucket::History);
    for (state, bucket) in [
        ("applying", OrchestrationBoardBucket::Active),
        ("attention", OrchestrationBoardBucket::Attention),
        ("retired", OrchestrationBoardBucket::History),
    ] {
        sqlx::query("UPDATE workflowCleanup SET state=? WHERE id=?")
            .bind(state)
            .bind(&first.items[0].id)
            .execute(store.pool())
            .await
            .unwrap();
        let board = store
            .orchestration_board_snapshot(&OrchestrationBoardQuery::default())
            .await
            .unwrap();
        assert!(board.revision > before.revision);
        assert_eq!(board.items[0].bucket, bucket);
        assert_eq!(board.items[0].cleanup_attention, state == "attention");
        assert_eq!(board.items[0].cleanup_applying, state == "applying");
        assert_eq!(board.counts.attention, i64::from(state == "attention"));
    }
    let foreign = WorkflowCleanupQuery {
        run_id: "foreign".into(),
        before_row: None,
    };
    assert!(store
        .workflow_cleanups(&foreign)
        .await
        .unwrap()
        .items
        .is_empty());
    assert!(store
        .workflow_cleanup_resources(&foreign)
        .await
        .unwrap()
        .items
        .is_empty());
}
