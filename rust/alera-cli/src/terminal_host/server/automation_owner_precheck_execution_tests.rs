use super::*;
use crate::terminal_host::server::automation_dispatch::automation_local_precheck::run_owner_precheck;
use alera_core::runtime::{
    OwnerAutomationPrecheckOutcome, OwnerAutomationPrecheckRequest, WorkspaceProcessJobPhase,
};

#[tokio::test]
async fn owner_precheck_executes_once_and_persists_verified_result_without_a_workspace() {
    let (fixture, _) = empty_project().await;
    let store = fixture.actor.runtime_store.clone();
    let marker = fixture.repo_path.join("owner-precheck-count");
    let request = OwnerAutomationPrecheckRequest {
        operation_id: uuid::Uuid::new_v4().to_string(),
        workspace: None,
        origin_id: "fixture-home".into(),
        run_id: "fixture-run".into(),
        project_id: "project-1".into(),
        path: fixture
            .repo_path
            .canonicalize()
            .unwrap()
            .to_str()
            .unwrap()
            .into(),
        precheck: alera_core::runtime::AutomationPrecheck {
            command: format!(
                "printf x >> {}; exit 1",
                crate::ssh_bootstrap::shell_quote(marker.to_str().unwrap())
            ),
            timeout_seconds: 10,
        },
    };
    store
        .register_owner_automation_precheck(&request)
        .await
        .unwrap();
    let completed = run_owner_precheck(&store, &request).await.unwrap();
    assert_eq!(
        completed.outcome,
        Some(OwnerAutomationPrecheckOutcome::Rejected)
    );
    assert_eq!(
        run_owner_precheck(&store, &request).await.unwrap(),
        completed
    );
    assert_eq!(std::fs::read_to_string(&marker).unwrap(), "x");
    let evidence = store
        .automation_precheck_processes(completed.process_id.as_deref().unwrap())
        .await
        .unwrap();
    assert_eq!(evidence.len(), 1);
    assert_eq!(evidence[0].phase, WorkspaceProcessJobPhase::ClosureVerified);
    assert!(evidence[0].pid.is_some());
    assert!(store.list_workspaces("project-1").await.unwrap().is_empty());
}
