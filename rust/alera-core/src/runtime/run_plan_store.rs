use anyhow::{anyhow, bail, Result};
use sqlx::Row;

use super::{
    AgentProfile, CreateRun, PrepareWorkflowPlan, RunActor, RunIsolation, RunPlanInput,
    RunPlanTaskInput, RuntimeStore, WorkflowPlanRevision,
};

impl RuntimeStore {
    /// Creates an isolated run that requires approval and proposes this exact
    /// plan for it in one call. A `run_id` proposes the next revision of a
    /// run that is planning again after a change request.
    pub async fn prepare_workflow_plan(
        &self,
        request: PrepareWorkflowPlan,
        validate_profile: fn(&AgentProfile) -> Result<()>,
    ) -> Result<WorkflowPlanRevision> {
        let actor = RunActor::runtime();
        let run_id = match &request.run_id {
            Some(run_id) => run_id.clone(),
            None => {
                let proposal = &request.proposal;
                let (created, _) = self
                    .create_run_with(
                        CreateRun {
                            request_id: request.request_id.clone(),
                            workspace_id: request.workspace_id.clone(),
                            objective: proposal.objective.clone(),
                            recipe_source: Some(proposal.recipe_source.clone()),
                            isolation: Some(RunIsolation::Isolated),
                            coordinator_profile_id: proposal.coordinator_profile_id.clone(),
                            role_profiles: proposal.role_profiles.clone(),
                            worker_profile_id: None,
                            max_concurrent: Some(proposal.max_concurrent),
                            approval_required: true,
                            stall_policy: None,
                        },
                        validate_profile,
                        &actor,
                        false,
                    )
                    .await?;
                created.run_id
            }
        };
        let tasks = request
            .proposal
            .tasks
            .iter()
            .map(|task| RunPlanTaskInput {
                id: task.id.clone(),
                title: task.title.clone(),
                spec: task.spec.clone(),
                stage_id: task.stage_id.clone(),
                role_id: Some(task.role_id.clone()),
                depends_on: task.depends_on.clone(),
                inputs: Some(task.inputs.clone()),
                corrects_task_id: task.corrects_task_id.clone(),
            })
            .collect();
        let proposed = self
            .propose_run_plan(
                &run_id,
                RunPlanInput {
                    request_id: Some(format!("{}.plan", request.request_id)),
                    stages: Vec::new(),
                    tasks,
                    stall_policy: None,
                    max_concurrent: Some(request.proposal.max_concurrent),
                },
                &actor,
            )
            .await?;
        if proposed.status == "planning" {
            bail!("run plan was not accepted");
        }
        self.workflow_plan_revision(&run_id, Some(proposed.revision))
            .await
    }

    /// A revision of an isolated run's plan (the current one by default).
    pub async fn workflow_plan_revision(
        &self,
        run_id: &str,
        revision: Option<i64>,
    ) -> Result<WorkflowPlanRevision> {
        let row = sqlx::query(
            "SELECT r.workspace_id, r.status, r.integration_sha, r.plan_revision AS current_revision,
                p.revision, p.snapshot, p.previous_revision, p.change_reason
            FROM orchestrationCoordinatorRuns r JOIN runPlanRevisions p ON p.run_id = r.id
              AND p.revision = COALESCE(?, r.plan_revision)
            WHERE r.id = ? AND r.isolation = 'isolated'",
        )
        .bind(revision)
        .bind(run_id)
        .fetch_optional(self.pool())
        .await?
        .ok_or_else(|| anyhow!("run plan not found"))?;
        Ok(WorkflowPlanRevision {
            run_id: run_id.to_owned(),
            workspace_id: row.try_get("workspace_id")?,
            revision: row.try_get("revision")?,
            status: row.try_get("status")?,
            current_revision: row.try_get("current_revision")?,
            integration_sha: row
                .try_get::<Option<String>, _>("integration_sha")?
                .unwrap_or_default(),
            plan: serde_json::from_str(&row.try_get::<String, _>("snapshot")?)?,
            previous_revision: row.try_get("previous_revision")?,
            change_reason: row.try_get("change_reason")?,
        })
    }
}
