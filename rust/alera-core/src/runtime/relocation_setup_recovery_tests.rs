use super::*;
use crate::runtime::{ProjectConfig, RelocationSetupReceipt, SetupRootProcessPhase};

async fn attempted(store: &RuntimeStore) -> RelocationSetupReceipt {
    let relocation = prepared(store).await;
    store.begin_workspace_relocation(&relocation).await.unwrap();
    let receipt = store
        .prepare_relocation_setup(&relocation.id, &ProjectConfig::default())
        .await
        .unwrap();
    let relocation = ready(store, relocation).await;
    store
        .commit_workspace_relocation(&relocation)
        .await
        .unwrap();
    let committed = store
        .find_workspace_relocation(&relocation.id)
        .await
        .unwrap()
        .unwrap();
    store
        .advance_workspace_relocation(&committed, Phase::Completed, None)
        .await
        .unwrap();
    store.claim_relocation_setup(&receipt).await.unwrap()
}

#[tokio::test]
async fn setup_recovery_requires_closure_evidence_and_keeps_original_records() {
    let (directory, store, _) = fixture().await;
    let receipt = attempted(&store).await;
    let starting = store
        .begin_setup_root_process(&receipt, 0, "linux", Some("boot-one"))
        .await
        .unwrap();
    let started = crate::runtime::RelocationSetupProcess {
        phase: SetupRootProcessPhase::Started,
        pid: Some(123),
        start_marker: Some(456),
        ..starting.clone()
    };
    store
        .update_setup_root_process(&receipt, &starting, &started)
        .await
        .unwrap();
    store
        .record_setup_descendant(&receipt, &started, 124, 457)
        .await
        .unwrap();
    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    for (platform, boot) in [
        ("linux", Some("boot-one")),
        ("linux", None),
        ("windows", Some("boot-two")),
    ] {
        assert!(reopened
            .recover_interrupted_relocation_setup(&receipt, platform, boot)
            .await
            .is_err());
    }
    assert!(reopened
        .validate_workspace_setup_idle("task")
        .await
        .is_err());
    assert_eq!(
        reopened.list_setup_root_processes(&receipt).await.unwrap(),
        vec![started]
    );
    let mut stale = receipt.clone();
    stale.attempt_id = Some("another-attempt".into());
    assert!(reopened
        .recover_interrupted_relocation_setup(&stale, "linux", Some("boot-two"))
        .await
        .is_err());
    let report = reopened
        .recover_interrupted_relocation_setup(&receipt, "linux", Some("boot-two"))
        .await
        .unwrap();
    assert_eq!(report.steps.len(), 1);
    assert!(!report.steps[0].succeeded);
    reopened
        .validate_workspace_setup_idle("task")
        .await
        .unwrap();
    assert_eq!(
        reopened
            .recover_interrupted_relocation_setup(&receipt, "linux", Some("boot-two"))
            .await
            .unwrap(),
        report
    );
    assert!(reopened
        .list_setup_descendants(&receipt)
        .await
        .unwrap()
        .iter()
        .all(|process| process.exit_verified));
    let evidence: String = sqlx::query_scalar(
        "SELECT dataJson FROM relocationSetupRecoveryEvidence WHERE relocationId = ?",
    )
    .bind(&receipt.relocation_id)
    .fetch_one(reopened.pool())
    .await
    .unwrap();
    let evidence: serde_json::Value = serde_json::from_str(&evidence).unwrap();
    assert_eq!(evidence["roots"][0]["phase"], "started");
    assert_eq!(evidence["descendants"][0]["exitVerified"], false);
    assert_eq!(evidence["bootId"], "boot-two");
}

#[tokio::test]
async fn setup_recovery_without_spawned_commands_records_failure_without_rerunning() {
    let (_directory, store, _) = fixture().await;
    let receipt = attempted(&store).await;
    let report = store
        .recover_interrupted_relocation_setup(&receipt, "windows", None)
        .await
        .unwrap();
    assert!(!report.steps[0].succeeded);
    assert!(store
        .list_setup_root_processes(&receipt)
        .await
        .unwrap()
        .is_empty());
    assert_eq!(
        store
            .find_relocation_setup(&receipt.relocation_id)
            .await
            .unwrap()
            .unwrap()
            .report,
        Some(report)
    );
    assert!(store.claim_relocation_setup(&receipt).await.is_err());
}
