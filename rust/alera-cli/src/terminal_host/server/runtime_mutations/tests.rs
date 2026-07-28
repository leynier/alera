use alera_core::runtime::{RuntimeStore, WorkspaceTabRecord};
use chrono::Utc;
use serde_json::json;

use crate::terminal_host::protocol::MOBILE_EMULATOR_TAB_KIND;

use super::{run_runtime_mutation, RuntimeMutationEffect, RuntimeMutationRequest};

#[tokio::test]
async fn sleep_reports_committed_effect_when_activity_recording_fails() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    store
        .upsert_workspace_tab(WorkspaceTabRecord {
            id: "emulator-tab".into(),
            workspace_id: "force-activity-failure".into(),
            kind: MOBILE_EMULATOR_TAB_KIND.into(),
            title: "Android".into(),
            payload: json!({}),
            created_at: Utc::now(),
            updated_at: Utc::now(),
        })
        .await
        .unwrap();

    let outcome = run_runtime_mutation(
        None,
        store.clone(),
        RuntimeMutationRequest::SleepWorkspace {
            workspace_id: "force-activity-failure".into(),
        },
    )
    .await;

    assert!(outcome.result.is_err());
    assert_eq!(outcome.committed_tab_ids, ["emulator-tab"]);
    assert!(matches!(
        outcome.effect_on_error,
        Some(RuntimeMutationEffect::WorkspaceSlept { workspace_id })
            if workspace_id == "force-activity-failure"
    ));
    assert!(store
        .find_workspace_tab("emulator-tab")
        .await
        .unwrap()
        .is_none());
}
