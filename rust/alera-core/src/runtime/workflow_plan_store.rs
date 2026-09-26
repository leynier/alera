use std::collections::BTreeSet;

use anyhow::{anyhow, bail, Result};
use sqlx::{Row, Sqlite, Transaction};

use super::workflow_catalog::workflow_blocking;
use super::workflow_plan::{workflow_digest, workflow_text};
use super::workflow_plan_compilation::compile_plan;
use super::{
    PrepareWorkflowPlan, ProjectKind, RuntimeStore, WorkflowPlanRevision, WorkflowPlanSnapshot,
    WorkflowRecipeSnapshot, WorkflowRecipeSource, WorkspaceStatus, LOCAL_HOST_ID,
    WORKFLOW_PLAN_MAX_BYTES,
};

impl RuntimeStore {
    pub async fn prepare_workflow_plan(
        &self,
        request: PrepareWorkflowPlan,
        validate_profile: fn(&super::AgentProfile) -> Result<()>,
    ) -> Result<WorkflowPlanRevision> {
        workflow_text(&request.request_id, 160)?;
        workflow_text(&request.workspace_id, 160)?;
        if request.run_id.is_some() != request.expected_revision.is_some() {
            bail!("workflow revision requires a run and its expected revision");
        }
        let digest_request = request.clone();
        let request_digest = workflow_blocking(move || {
            super::orchestration_contract_schema::bounded_json(
                &serde_json::to_value(&digest_request)?,
                WORKFLOW_PLAN_MAX_BYTES,
            )?;
            workflow_digest(&digest_request)
        })
        .await?;
        if let Some(previous) = self
            .workflow_prepare_receipt(&request.request_id, &request_digest)
            .await?
        {
            return Ok(previous);
        }
        let workspace = self
            .find_workspace(&request.workspace_id)
            .await?
            .ok_or_else(|| anyhow!("workflow workspace not found"))?;
        let project = self
            .find_project(&workspace.project_id)
            .await?
            .ok_or_else(|| anyhow!("workflow project not found"))?;
        if workspace.status != WorkspaceStatus::Active
            || workspace.host_id != LOCAL_HOST_ID
            || project.kind != ProjectKind::GitRepository
        {
            bail!("workflows require an active local Git workspace");
        }
        if matches!(&request.proposal.recipe_source, WorkflowRecipeSource::Project { workspace_id, .. }
            if workspace_id != &request.workspace_id)
        {
            bail!("project recipe must belong to the run workspace");
        }
        let selected = self
            .workflow_catalog_recipe(&request.proposal.recipe_source)
            .await?;
        let required = request
            .proposal
            .role_profiles
            .values()
            .cloned()
            .chain(std::iter::once(
                request.proposal.coordinator_profile_id.clone(),
            ))
            .collect::<BTreeSet<_>>();
        let profiles = self
            .list_agent_profiles()
            .await?
            .into_iter()
            .filter(|profile| required.contains(&profile.id))
            .map(|profile| (profile.id.clone(), profile))
            .collect();
        let proposal = request.proposal.clone();
        let plan = workflow_blocking(move || {
            let recipe = WorkflowRecipeSnapshot::freeze(selected.source, selected.recipe)?;
            let source_workspace = super::WorkflowSourceWorkspace {
                workspace_id: workspace.id.clone(),
                instance_id: workspace.instance_id,
                project_id: workspace.project_id,
                path: workspace.path.clone(),
                project_repo_path: project.repo_path,
            };
            let plan = compile_plan(proposal, recipe, profiles, source_workspace)?;
            for profile in plan.profiles.values() {
                validate_profile(profile)?;
            }
            let repository = git2::Repository::open(&workspace.path)
                .map_err(|_| anyhow!("workflow source repository is unavailable"))?;
            let oid = git2::Oid::from_str(&plan.source_sha)?;
            repository
                .find_commit(oid)
                .map_err(|_| anyhow!("workflow source commit is unavailable"))?;
            Ok(plan)
        })
        .await?;
        self.persist_workflow_plan(&request, &request_digest, &plan)
            .await
    }

    async fn workflow_prepare_receipt(
        &self,
        request_id: &str,
        digest: &str,
    ) -> Result<Option<WorkflowPlanRevision>> {
        let row = sqlx::query("SELECT run_id, revision, request_digest FROM workflowPlanRevisions WHERE request_id = ?")
            .bind(request_id).fetch_optional(self.pool()).await?;
        let Some(row) = row else {
            return Ok(None);
        };
        if row.try_get::<String, _>("request_digest")? != digest {
            bail!("workflow request id was already used for different contents");
        }
        self.workflow_plan_revision(
            &row.try_get::<String, _>("run_id")?,
            Some(row.try_get("revision")?),
        )
        .await
        .map(Some)
    }

    pub(super) async fn persist_workflow_plan(
        &self,
        request: &PrepareWorkflowPlan,
        request_digest: &str,
        plan: &WorkflowPlanSnapshot,
    ) -> Result<WorkflowPlanRevision> {
        let mut tx = self.pool().begin().await?;
        // Acquire the writer before checking idempotency/CAS, so simultaneous
        // requests serialize without a read-to-write SQLite upgrade race.
        sqlx::query("UPDATE orchestrationBoardRevision SET revision = revision WHERE id = 1")
            .execute(&mut *tx)
            .await?;
        if let Some(row) = sqlx::query("SELECT run_id, revision, request_digest FROM workflowPlanRevisions WHERE request_id = ?")
            .bind(&request.request_id).fetch_optional(&mut *tx).await?
        {
            if row.try_get::<String, _>("request_digest")? != request_digest {
                bail!("workflow request id was already used for different contents");
            }
            let run_id: String = row.try_get("run_id")?;
            let revision = row.try_get("revision")?;
            tx.commit().await?;
            return self.workflow_plan_revision(&run_id, Some(revision)).await;
        }
        let run_id = request
            .run_id
            .clone()
            .unwrap_or_else(|| format!("run_{}", uuid::Uuid::new_v4()));
        super::workflow_source_identity::require_source_workspace(&mut tx, &plan.source_workspace)
            .await?;
        let revision = if let Some(expected) = request.expected_revision {
            let row = sqlx::query(
                "SELECT revision, status, workspace_id FROM workflowRuns WHERE run_id = ?",
            )
            .bind(&run_id)
            .fetch_one(&mut *tx)
            .await?;
            if row.try_get::<i64, _>("revision")? != expected
                || row.try_get::<String, _>("workspace_id")? != request.workspace_id
                || !matches!(
                    row.try_get::<String, _>("status")?.as_str(),
                    "prepared" | "changesRequested" | "rejected"
                )
            {
                bail!("workflow plan changed or is not open for revision");
            }
            ensure_no_active_work(&mut tx, &run_id).await?;
            let previous: String = sqlx::query_scalar(
                "SELECT snapshot FROM workflowPlanRevisions WHERE run_id = ? AND revision = ?",
            )
            .bind(&run_id)
            .bind(expected)
            .fetch_one(&mut *tx)
            .await?;
            let previous: WorkflowPlanSnapshot = serde_json::from_str(&previous)?;
            if previous.source_sha != plan.source_sha
                || previous.source_workspace != plan.source_workspace
            {
                bail!("workflow correction must preserve the original source commit");
            }
            sqlx::query(
                "UPDATE workflowRuns SET revision = ?, status = 'prepared' WHERE run_id = ?",
            )
            .bind(expected + 1)
            .bind(&run_id)
            .execute(&mut *tx)
            .await?;
            expected + 1
        } else {
            sqlx::query(
                "INSERT INTO orchestrationCoordinatorRuns
                (id, spec, status, workspace_id, max_concurrent, execution_policy_status)
                VALUES (?, ?, 'idle', ?, ?, 'draft')",
            )
            .bind(&run_id)
            .bind(&plan.objective)
            .bind(&request.workspace_id)
            .bind(plan.max_concurrent)
            .execute(&mut *tx)
            .await?;
            sqlx::query(
                "INSERT INTO workflowRuns(run_id, workspace_id, revision, status, integration_sha)
                VALUES (?, ?, 1, 'prepared', ?)",
            )
            .bind(&run_id)
            .bind(&request.workspace_id)
            .bind(&plan.source_sha)
            .execute(&mut *tx)
            .await?;
            1
        };
        for task in &plan.tasks {
            if let Some(corrects) = &task.task.corrects_task_id {
                let member: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM workflowPlanTasks WHERE run_id = ? AND task_id = ?)")
                    .bind(&run_id).bind(corrects).fetch_one(&mut *tx).await?;
                if !member {
                    bail!("workflow correction references a task outside this run");
                }
            }
        }
        sqlx::query(
            "INSERT INTO workflowPlanRevisions
            (run_id, revision, request_id, request_digest, snapshot, digest, previous_revision)
            VALUES (?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(&run_id)
        .bind(revision)
        .bind(&request.request_id)
        .bind(request_digest)
        .bind(serde_json::to_string(plan)?)
        .bind(&plan.digest)
        .bind(request.expected_revision)
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "UPDATE orchestrationCoordinatorRuns SET spec = ?, max_concurrent = ?,
            execution_policy_status = 'draft', last_activity_at = datetime('now') WHERE id = ?",
        )
        .bind(&plan.objective)
        .bind(plan.max_concurrent)
        .bind(&run_id)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        self.workflow_plan_revision(&run_id, Some(revision)).await
    }

    pub async fn workflow_plan_revision(
        &self,
        run_id: &str,
        revision: Option<i64>,
    ) -> Result<WorkflowPlanRevision> {
        let row = sqlx::query("SELECT r.workspace_id, r.status, r.integration_sha, r.revision AS current_revision, p.revision,
            p.snapshot, p.previous_revision, p.change_reason
            FROM workflowRuns r JOIN workflowPlanRevisions p ON p.run_id = r.run_id
            AND p.revision = COALESCE(?, r.revision) WHERE r.run_id = ?")
            .bind(revision).bind(run_id).fetch_optional(self.pool()).await?
            .ok_or_else(|| anyhow!("workflow plan not found"))?;
        Ok(WorkflowPlanRevision {
            run_id: run_id.to_owned(),
            workspace_id: row.try_get("workspace_id")?,
            revision: row.try_get("revision")?,
            status: row.try_get("status")?,
            current_revision: row.try_get("current_revision")?,
            integration_sha: row.try_get("integration_sha")?,
            plan: serde_json::from_str(&row.try_get::<String, _>("snapshot")?)?,
            previous_revision: row.try_get("previous_revision")?,
            change_reason: row.try_get("change_reason")?,
        })
    }

    pub async fn ensure_legacy_workflow_dispatch_allowed(&self, task_id: &str) -> Result<()> {
        let workflow: bool = sqlx::query_scalar("SELECT EXISTS(
            SELECT 1 FROM workflowPlanTasks WHERE task_id = ?
            UNION ALL SELECT 1 FROM orchestrationTasks t JOIN workflowRuns w ON w.run_id = t.run_id WHERE t.id = ?)")
            .bind(task_id).bind(task_id).fetch_one(self.pool()).await?;
        if workflow {
            bail!("workflow execution requires managed isolation and integration");
        }
        Ok(())
    }
}

pub(super) async fn ensure_no_active_work(
    tx: &mut Transaction<'_, Sqlite>,
    run_id: &str,
) -> Result<()> {
    let active: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM orchestrationTasks WHERE run_id = ? AND status IN ('dispatched','stalled'))")
        .bind(run_id).fetch_one(&mut **tx).await?;
    if active {
        bail!("stop active workflow attempts before requesting a correction");
    }
    Ok(())
}
