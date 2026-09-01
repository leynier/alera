use serde_json::json;

use super::*;
use crate::runtime::workflow_plan_tests::{decision, fixture, valid_profile};
use crate::workflow_approval::WorkflowDecision;

pub(super) struct Fixture {
    pub directory: tempfile::TempDir,
    pub store: RuntimeStore,
    pub plan: WorkflowPlanRevision,
    pub input: IntegrateWorkflowResult,
    pub source_sha: String,
    pub dependent: String,
    pub dispatch: String,
}

impl Fixture {
    pub async fn new() -> Self {
        let (directory, store, proposal) = fixture(false).await;
        let plan = store
            .prepare_workflow_plan(proposal, valid_profile)
            .await
            .unwrap();
        decision(directory.path(), &store, &plan, WorkflowDecision::Approve).await;
        ready_workspace(&directory, &store, &plan, None).await;
        let task: String = sqlx::query_scalar(
            "SELECT task_id FROM workflowPlanTasks WHERE run_id = ? AND logical_id = 'fix'",
        )
        .bind(&plan.run_id)
        .fetch_one(store.pool())
        .await
        .unwrap();
        let dependent = sqlx::query_scalar(
            "SELECT task_id FROM workflowPlanTasks WHERE run_id = ? AND logical_id = 'verify'",
        )
        .bind(&plan.run_id)
        .fetch_one(store.pool())
        .await
        .unwrap();
        let workspace = ready_workspace(&directory, &store, &plan, Some(task.clone())).await;
        let (launch, _) = store
            .reserve_workflow_launch(
                &LaunchWorkflowTask {
                    request_id: "launch-result".into(),
                    run_id: plan.run_id.clone(),
                    revision: 1,
                    task_id: task.clone(),
                    workspace_id: workspace.identity.workspace.id.clone(),
                },
                &"a".repeat(64),
            )
            .await
            .unwrap();
        store.claim_workflow_launch(&launch.id).await.unwrap();
        store
            .mark_workflow_launch_started(&launch.id)
            .await
            .unwrap();
        store
            .accept_orchestration_dispatch(
                &launch.dispatch_id,
                &launch.terminal_handle,
                &"a".repeat(64),
            )
            .await
            .unwrap();
        let repo = git2::Repository::open(&workspace.identity.workspace.path).unwrap();
        let mut config = repo.config().unwrap();
        config.set_str("user.name", "Workflow Test").unwrap();
        config
            .set_str("user.email", "workflow@example.invalid")
            .unwrap();
        std::fs::write(
            std::path::Path::new(&workspace.identity.workspace.path).join("result.txt"),
            "done\n",
        )
        .unwrap();
        let mut index = repo.index().unwrap();
        index.add_path(std::path::Path::new("result.txt")).unwrap();
        index.write().unwrap();
        let tree = repo.find_tree(index.write_tree().unwrap()).unwrap();
        let signature = repo.signature().unwrap();
        let parent = repo.head().unwrap().peel_to_commit().unwrap();
        let source_sha = repo
            .commit(
                Some("HEAD"),
                &signature,
                &signature,
                "test: complete task",
                &tree,
                &[&parent],
            )
            .unwrap()
            .to_string();
        let dispatch = launch.dispatch_id;
        let contract = &plan
            .plan
            .tasks
            .iter()
            .find(|t| t.task.id == "fix")
            .unwrap()
            .contract
            .contract;
        let result = json!({"completionKind":"success", "summary":"Fixed", "artifacts":["result.txt"],
            "filesModified":["result.txt"], "validation":contract.checklist.iter()
                .map(|c| json!({"id":c.id,"passed":true,"evidence":"focused checks passed"})).collect::<Vec<_>>()});
        store
            .complete_workflow_orchestration_dispatch(
                &dispatch,
                &launch.terminal_handle,
                &result.to_string(),
                &source_sha,
            )
            .await
            .unwrap();
        let input = IntegrateWorkflowResult {
            request_id: "integrate-result".into(),
            run_id: plan.run_id.clone(),
            revision: 1,
            task_id: task,
            workspace_id: workspace.identity.workspace.id,
        };
        Self {
            directory,
            store,
            plan,
            input,
            source_sha,
            dependent,
            dispatch,
        }
    }

    pub async fn reserve(&self) -> WorkflowIntegrationRecord {
        self.store
            .reserve_workflow_integration(&self.input)
            .await
            .unwrap()
    }

    pub async fn assert_dependent_blocked(&self) {
        let mut tx = self.store.pool().begin().await.unwrap();
        assert!(eligible_task(
            &mut tx,
            &self.plan.run_id,
            1,
            &self.dependent,
            &self.plan.plan
        )
        .await
        .is_err());
        let status: String =
            sqlx::query_scalar("SELECT status FROM orchestrationTasks WHERE id = ?")
                .bind(&self.dependent)
                .fetch_one(&mut *tx)
                .await
                .unwrap();
        assert_eq!(status, "pending");
    }
}

pub(in crate::runtime) async fn ready_workspace(
    directory: &tempfile::TempDir,
    store: &RuntimeStore,
    plan: &WorkflowPlanRevision,
    task_id: Option<String>,
) -> WorkflowWorkspaceRecord {
    let mut candidate = store.find_workspace("workspace").await.unwrap().unwrap();
    candidate.id = uuid::Uuid::new_v4().to_string();
    candidate.instance_id = uuid::Uuid::new_v4().to_string();
    candidate.path = directory
        .path()
        .join(&candidate.id)
        .to_str()
        .unwrap()
        .into();
    candidate.branch = Some(format!("alera/workflows/{}", candidate.id));
    candidate.kind = WorkspaceKind::Linked;
    let request = PrepareWorkflowWorkspace {
        request_id: candidate.id.clone(),
        run_id: plan.run_id.clone(),
        revision: 1,
        task_id,
        retry_of: None,
    };
    let record = store
        .reserve_workflow_workspace(&request, candidate)
        .await
        .unwrap();
    let identity = &record.identity;
    crate::git::ensure_workflow_worktree(
        &identity.repo_path,
        &identity.workspace.path,
        &identity.base_sha,
        &identity.workspace.id,
    )
    .unwrap();
    for (old, new) in [
        (
            WorkflowWorkspacePhase::Reserved,
            WorkflowWorkspacePhase::Creating,
        ),
        (
            WorkflowWorkspacePhase::Creating,
            WorkflowWorkspacePhase::Created,
        ),
        (
            WorkflowWorkspacePhase::Created,
            WorkflowWorkspacePhase::Ready,
        ),
    ] {
        store
            .transition_workflow_workspace(&identity.workspace.id, 1, old, new, None, None)
            .await
            .unwrap();
    }
    store
        .workflow_workspace(&identity.workspace.id)
        .await
        .unwrap()
}
