use std::collections::BTreeMap;

use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use sqlx::Row;

use super::workflow_catalog::workflow_blocking;
use super::workflow_plan::{workflow_digest, workflow_text};
use super::{
    AgentProfile, PrepareWorkflowPlan, RuntimeStore, WorkflowPlanProposal, WorkflowProposalDraft,
};

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CreateWorkflowCorrection {
    pub request_id: String,
    pub run_id: String,
    pub revision: i64,
    pub plan_digest: String,
    pub reason: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowCorrectionContext {
    pub revision: i64,
    pub plan_digest: String,
    pub integration_sha: String,
    pub reason: String,
    pub prior_tasks: Vec<WorkflowCorrectionTask>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowCorrectionTask {
    pub task_id: String,
    pub logical_id: String,
    pub status: String,
    pub result_preview: Option<String>,
    pub result_truncated: bool,
    pub integration_sha: Option<String>,
}

impl RuntimeStore {
    pub async fn create_workflow_correction(
        &self,
        request: CreateWorkflowCorrection,
        validate_profile: fn(&AgentProfile) -> Result<()>,
    ) -> Result<WorkflowProposalDraft> {
        workflow_text(&request.request_id, 160)?;
        if !request
            .request_id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
            || !request.request_id.as_bytes()[0].is_ascii_alphanumeric()
        {
            bail!("workflow correction requires a portable proposal id");
        }
        workflow_text(&request.run_id, 160)?;
        workflow_text(&request.reason, 4096)?;
        workflow_text(&request.plan_digest, 64)?;
        let digest = workflow_digest(&("workflow-correction-v1", &request))?;
        if let Some(saved) = self.proposal_receipt(&request.request_id, &digest).await? {
            return Ok(saved);
        }
        let current = self
            .workflow_plan_revision(&request.run_id, Some(request.revision))
            .await?;
        if current.current_revision != request.revision
            || current.plan.digest != request.plan_digest
        {
            bail!("workflow correction is stale; refresh the current revision");
        }
        let frozen_request = request.clone();
        let mut draft = workflow_blocking(move || {
            let mut selection = current.plan;
            if selection.content_digest()? != selection.digest {
                bail!("workflow plan snapshot is invalid");
            }
            let mut role_profiles = BTreeMap::new();
            for task in &selection.tasks {
                if role_profiles
                    .insert(task.task.role_id.clone(), task.profile_id.clone())
                    .is_some_and(|previous| previous != task.profile_id)
                {
                    bail!("workflow role has conflicting frozen profile bindings");
                }
            }
            let proposal = WorkflowPlanProposal {
                objective: selection.objective.clone(),
                source_sha: selection.source_sha.clone(),
                recipe_source: selection.recipe.source.clone(),
                expected_recipe_digest: selection.recipe.recipe.content_digest()?,
                coordinator_profile_id: selection.coordinator_profile_id.clone(),
                role_profiles,
                max_concurrent: selection.max_concurrent,
                tasks: Vec::new(),
            };
            super::workflow_plan_compilation::validate_selection(
                &proposal,
                &selection.recipe,
                &selection.profiles,
            )?;
            for profile in selection.profiles.values() {
                validate_profile(profile)?;
            }
            let repository = git2::Repository::open(&selection.source_workspace.path)?;
            repository.find_commit(git2::Oid::from_str(&selection.source_sha)?)?;
            selection.tasks.clear();
            selection.digest = selection.content_digest()?;
            Ok(WorkflowProposalDraft {
                id: frozen_request.request_id.clone(),
                request: PrepareWorkflowPlan {
                    request_id: frozen_request.request_id,
                    workspace_id: current.workspace_id,
                    run_id: Some(frozen_request.run_id),
                    expected_revision: Some(frozen_request.revision),
                    proposal,
                },
                selection,
                correction: Some(WorkflowCorrectionContext {
                    revision: frozen_request.revision,
                    plan_digest: frozen_request.plan_digest,
                    integration_sha: current.integration_sha,
                    reason: frozen_request.reason,
                    prior_tasks: Vec::new(),
                }),
            })
        })
        .await?;
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision=revision WHERE id=1")
            .execute(&mut *tx)
            .await?;
        if let Some(row) =
            sqlx::query("SELECT request_digest,document FROM workflowProposalDrafts WHERE id=?")
                .bind(&request.request_id)
                .fetch_optional(&mut *tx)
                .await?
        {
            if row.try_get::<String, _>("request_digest")? != digest {
                bail!("workflow proposal id was already used for different contents");
            }
            return Ok(serde_json::from_str(
                &row.try_get::<String, _>("document")?,
            )?);
        }
        super::workflow_source_identity::require_source_workspace(
            &mut tx,
            &draft.selection.source_workspace,
        )
        .await?;
        let valid:bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM workflowRuns w JOIN workflowPlanRevisions p ON p.run_id=w.run_id AND p.revision=w.revision
            JOIN orchestrationCoordinatorRuns c ON c.id=w.run_id
            WHERE w.run_id=? AND w.revision=? AND p.digest=? AND w.status IN ('prepared','changesRequested','rejected')
            AND c.status IN ('idle','running'))")
            .bind(&request.run_id).bind(request.revision).bind(&request.plan_digest).fetch_one(&mut *tx).await?;
        if !valid {
            bail!("workflow is not open for a correction proposal");
        }
        super::workflow_plan_store::ensure_no_active_work(&mut tx, &request.run_id).await?;
        let rows=sqlx::query("SELECT p.task_id,p.logical_id,t.status,substr(t.result,1,1024) AS result_preview,
            COALESCE(length(t.result)>1024,0) AS result_truncated,e.integration_sha
            FROM workflowPlanTasks p JOIN orchestrationTasks t ON t.id=p.task_id LEFT JOIN workflowTaskEvidence e ON e.task_id=p.task_id
            WHERE p.run_id=? AND p.revision=(SELECT MAX(revision) FROM workflowPlanTasks WHERE run_id=? AND revision<=?) ORDER BY p.logical_id LIMIT 129")
            .bind(&request.run_id).bind(&request.run_id).bind(request.revision).fetch_all(&mut *tx).await?;
        if rows.len() > 128 {
            bail!("workflow correction exceeds the task limit");
        }
        draft
            .correction
            .as_mut()
            .expect("correction context")
            .prior_tasks = rows
            .into_iter()
            .map(|row| {
                Ok(WorkflowCorrectionTask {
                    task_id: row.try_get("task_id")?,
                    logical_id: row.try_get("logical_id")?,
                    status: row.try_get("status")?,
                    result_preview: row.try_get("result_preview")?,
                    result_truncated: row.try_get("result_truncated")?,
                    integration_sha: row.try_get("integration_sha")?,
                })
            })
            .collect::<Result<Vec<_>>>()?;
        super::orchestration_contract_schema::bounded_json(
            &serde_json::to_value(&draft)?,
            super::WORKFLOW_PLAN_MAX_BYTES,
        )?;
        sqlx::query("INSERT INTO workflowProposalDrafts(id,request_digest,document) VALUES(?,?,?) ON CONFLICT(id) DO NOTHING")
            .bind(&draft.id).bind(&digest).bind(serde_json::to_string(&draft)?).execute(&mut *tx).await?;
        tx.commit().await?;
        self.proposal_receipt(&request.request_id, &digest)
            .await?
            .ok_or_else(|| anyhow::anyhow!("workflow correction receipt is unavailable"))
    }
}
