use std::collections::BTreeSet;

use anyhow::{anyhow, bail, Result};
use sqlx::Row;

use super::workflow_catalog::workflow_blocking;
use super::workflow_plan::{workflow_digest, workflow_text};
use super::{
    AgentProfile, PrepareWorkflowPlan, ProjectKind, RuntimeStore, WorkflowPlanSnapshot,
    WorkflowProposalDraft, WorkflowRecipeSnapshot, WorkflowRecipeSource, WorkflowSourceWorkspace,
    WorkspaceStatus, LOCAL_HOST_ID,
};

impl RuntimeStore {
    pub async fn create_workflow_proposal(
        &self,
        request: PrepareWorkflowPlan,
        validate_profile: fn(&AgentProfile) -> Result<()>,
    ) -> Result<WorkflowProposalDraft> {
        self.create_workflow_proposal_at_source(request, validate_profile, None)
            .await
    }

    pub async fn create_workflow_proposal_at_source(
        &self,
        request: PrepareWorkflowPlan,
        validate_profile: fn(&AgentProfile) -> Result<()>,
        expected_source: Option<WorkflowSourceWorkspace>,
    ) -> Result<WorkflowProposalDraft> {
        workflow_text(&request.request_id, 160)?;
        if !request
            .request_id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
            || !request.request_id.as_bytes()[0].is_ascii_alphanumeric()
        {
            bail!("workflow proposal id must be an alphanumeric identifier with optional hyphens or underscores");
        }
        workflow_text(&request.workspace_id, 160)?;
        if !request.proposal.tasks.is_empty()
            || request.run_id.is_some() != request.expected_revision.is_some()
        {
            bail!("workflow proposal requires an empty task list and a complete revision identity");
        }
        let digest_request = request.clone();
        let digest = workflow_blocking(move || {
            super::orchestration_contract_schema::bounded_json(
                &serde_json::to_value(&digest_request)?,
                super::WORKFLOW_PLAN_MAX_BYTES,
            )?;
            workflow_digest(&digest_request)
        })
        .await?;
        if let Some(saved) = self.proposal_receipt(&request.request_id, &digest).await? {
            if expected_source
                .as_ref()
                .is_some_and(|source| source != &saved.selection.source_workspace)
            {
                bail!("workflow proposal source does not match the original selection");
            }
            return Ok(saved);
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
        let recipe = self
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
        let frozen_request = request.clone();
        let draft = workflow_blocking(move || {
            let recipe = WorkflowRecipeSnapshot::freeze(recipe.source, recipe.recipe)?;
            let proposal = &frozen_request.proposal;
            super::workflow_plan_compilation::validate_selection(proposal, &recipe, &profiles)?;
            for profile in profiles.values() {
                validate_profile(profile)?;
            }
            let repository = git2::Repository::open(&workspace.path)
                .map_err(|_| anyhow!("workflow source repository is unavailable"))?;
            repository
                .find_commit(git2::Oid::from_str(&proposal.source_sha)?)
                .map_err(|_| anyhow!("workflow source commit is unavailable"))?;
            let mut selection = WorkflowPlanSnapshot {
                version: 1,
                source_workspace: WorkflowSourceWorkspace {
                    workspace_id: workspace.id,
                    instance_id: workspace.instance_id,
                    project_id: workspace.project_id,
                    path: workspace.path,
                    project_repo_path: project.repo_path,
                },
                objective: proposal.objective.clone(),
                source_sha: proposal.source_sha.clone(),
                recipe,
                coordinator_profile_id: proposal.coordinator_profile_id.clone(),
                profiles,
                max_concurrent: proposal.max_concurrent,
                tasks: Vec::new(),
                digest: String::new(),
            };
            selection.digest = selection.content_digest()?;
            super::orchestration_contract_schema::bounded_json(
                &serde_json::to_value(&selection)?,
                super::WORKFLOW_PLAN_MAX_BYTES,
            )?;
            Ok(WorkflowProposalDraft {
                id: frozen_request.request_id.clone(),
                request: frozen_request,
                selection,
            })
        })
        .await?;
        let document = serde_json::to_string(&draft)?;
        if expected_source
            .as_ref()
            .is_some_and(|source| source != &draft.selection.source_workspace)
        {
            bail!("workflow source workspace changed; select its current identity again");
        }
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision = revision WHERE id = 1")
            .execute(&mut *tx)
            .await?;
        super::workflow_source_identity::require_source_workspace(
            &mut tx,
            &draft.selection.source_workspace,
        )
        .await?;
        if let Some(run_id) = &request.run_id {
            let row = sqlx::query(
                "SELECT revision,status,workspace_id FROM workflowRuns WHERE run_id = ?",
            )
            .bind(run_id)
            .fetch_one(&mut *tx)
            .await?;
            if Some(row.try_get::<i64, _>("revision")?) != request.expected_revision
                || row.try_get::<String, _>("workspace_id")? != request.workspace_id
                || !matches!(
                    row.try_get::<String, _>("status")?.as_str(),
                    "prepared" | "changesRequested" | "rejected"
                )
            {
                bail!("workflow plan changed or is not open for revision");
            }
            super::workflow_plan_store::ensure_no_active_work(&mut tx, run_id).await?;
            let previous: String = sqlx::query_scalar(
                "SELECT snapshot FROM workflowPlanRevisions WHERE run_id = ? AND revision = ?",
            )
            .bind(run_id)
            .bind(request.expected_revision)
            .fetch_one(&mut *tx)
            .await?;
            let previous: WorkflowPlanSnapshot = serde_json::from_str(&previous)?;
            if previous.source_sha != draft.selection.source_sha
                || previous.source_workspace != draft.selection.source_workspace
            {
                bail!("workflow correction must preserve the source commit and workspace identity");
            }
        }
        sqlx::query("INSERT INTO workflowProposalDrafts(id,request_digest,document) VALUES(?,?,?) ON CONFLICT(id) DO NOTHING")
            .bind(&draft.id).bind(&digest).bind(document).execute(&mut *tx).await?;
        tx.commit().await?;
        self.proposal_receipt(&draft.id, &digest)
            .await?
            .ok_or_else(|| anyhow!("workflow proposal receipt is unavailable"))
    }

    async fn proposal_receipt(
        &self,
        id: &str,
        digest: &str,
    ) -> Result<Option<WorkflowProposalDraft>> {
        let row =
            sqlx::query("SELECT request_digest,document FROM workflowProposalDrafts WHERE id = ?")
                .bind(id)
                .fetch_optional(self.pool())
                .await?;
        let Some(row) = row else { return Ok(None) };
        if row.try_get::<String, _>("request_digest")? != digest {
            bail!("workflow proposal id was already used for different contents");
        }
        let document: String = row.try_get("document")?;
        workflow_blocking(move || Ok(Some(serde_json::from_str(&document)?))).await
    }
}
