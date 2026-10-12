//! `runs.create`: one call freezes the recipe, the profiles and the source,
//! inserts the run in `planning` and reserves its coordinator terminal. The
//! caller then launches the coordinator through the reserved terminal.

use std::collections::{BTreeMap, BTreeSet};

use anyhow::{anyhow, bail, Result};
use serde::{Deserialize, Serialize};
use sqlx::Row;

use super::run_catalog::workflow_blocking;
use super::run_event_store::{record_run_event, NewRunEvent, RunEventKind};
use super::run_plan::{workflow_digest, workflow_text};
use super::{
    AgentProfile, ProjectKind, RunActor, RunIsolation, RunSourceSnapshot, RuntimeStore,
    WorkflowCoordinatorReceipt, WorkflowPlanProposal, WorkflowRecipeSnapshot, WorkflowRecipeSource,
    WorkflowSourceWorkspace, WorkspaceStatus, LOCAL_HOST_ID,
};

pub const RUN_STALL_POLICIES: [&str; 3] = ["ask", "auto-failover", "wait"];
pub const FREEFORM_RECIPE_ID: &str = "freeform";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CreateRun {
    pub request_id: String,
    pub workspace_id: String,
    pub objective: String,
    #[serde(default)]
    pub recipe_source: Option<WorkflowRecipeSource>,
    #[serde(default)]
    pub isolation: Option<RunIsolation>,
    pub coordinator_profile_id: String,
    #[serde(default)]
    pub role_profiles: BTreeMap<String, String>,
    #[serde(default)]
    pub worker_profile_id: Option<String>,
    #[serde(default)]
    pub max_concurrent: Option<u32>,
    #[serde(default)]
    pub approval_required: bool,
    #[serde(default)]
    pub stall_policy: Option<String>,
}

/// The `runs.create` response; replayed verbatim for the same request id.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RunCreated {
    pub run_id: String,
    pub status: String,
    pub isolation: RunIsolation,
    pub coordinator_tab_id: Option<String>,
    pub coordinator_profile_id: String,
}

/// Frozen inputs the coordinator reads with `orchestration.planContext`.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct FrozenRunSelection {
    pub recipe: Option<WorkflowRecipeSnapshot>,
    pub profiles: BTreeMap<String, AgentProfile>,
    pub role_profiles: BTreeMap<String, String>,
    pub worker_profile_id: Option<String>,
}

impl RuntimeStore {
    /// Creates a run in `planning` and reserves its coordinator terminal.
    /// Returns the receipt and whether this call created it: only the creator
    /// launches the coordinator, so a replay never starts a second one.
    pub async fn create_run(
        &self,
        request: CreateRun,
        validate_profile: fn(&AgentProfile) -> Result<()>,
        actor: &RunActor,
    ) -> Result<(RunCreated, bool)> {
        self.create_run_with(request, validate_profile, actor, true)
            .await
    }

    /// Without `reserve_coordinator` the run has no coordinator terminal; its
    /// plan comes from the caller (`prepare_workflow_plan`).
    pub(super) async fn create_run_with(
        &self,
        request: CreateRun,
        validate_profile: fn(&AgentProfile) -> Result<()>,
        actor: &RunActor,
        reserve_coordinator: bool,
    ) -> Result<(RunCreated, bool)> {
        validate_create(&request)?;
        let digest = workflow_digest(&("runs.create", &request))?;
        if let Some(receipt) = self
            .run_command_receipt(&request.request_id, &digest)
            .await?
        {
            return Ok((serde_json::from_value(receipt)?, false));
        }
        let isolation = request.isolation.unwrap_or_default();
        let workspace = self
            .find_workspace(&request.workspace_id)
            .await?
            .ok_or_else(|| anyhow!("run workspace not found"))?;
        let project = self
            .find_project(&workspace.project_id)
            .await?
            .ok_or_else(|| anyhow!("run project not found"))?;
        if workspace.status != WorkspaceStatus::Active {
            bail!("runs require an active workspace");
        }
        if isolation == RunIsolation::Isolated
            && (workspace.host_id != LOCAL_HOST_ID || project.kind != ProjectKind::GitRepository)
        {
            bail!("isolated runs require an active local Git workspace");
        }
        let recipe_source = match (isolation, request.recipe_source.clone()) {
            (RunIsolation::Shared, Some(_)) => bail!("shared runs do not use a recipe"),
            (RunIsolation::Shared, None) => None,
            (RunIsolation::Isolated, Some(source)) => Some(source),
            (RunIsolation::Isolated, None) => Some(WorkflowRecipeSource::BuiltIn {
                id: FREEFORM_RECIPE_ID.into(),
            }),
        };
        if matches!(&recipe_source, Some(WorkflowRecipeSource::Project { workspace_id, .. })
            if workspace_id != &request.workspace_id)
        {
            bail!("project recipe must belong to the run workspace");
        }
        let selected = match &recipe_source {
            Some(source) => Some(self.workflow_catalog_recipe(source).await?),
            None => None,
        };
        let worker = request
            .worker_profile_id
            .clone()
            .unwrap_or_else(|| request.coordinator_profile_id.clone());
        let mut role_profiles = request.role_profiles.clone();
        if let Some(selected) = &selected {
            for role in &selected.recipe.roles {
                role_profiles
                    .entry(role.id.clone())
                    .or_insert_with(|| worker.clone());
            }
        }
        let required = role_profiles
            .values()
            .cloned()
            .chain([request.coordinator_profile_id.clone(), worker.clone()])
            .collect::<BTreeSet<_>>();
        let profiles = self
            .list_agent_profiles()
            .await?
            .into_iter()
            .filter(|profile| required.contains(&profile.id))
            .map(|profile| (profile.id.clone(), profile))
            .collect::<BTreeMap<_, _>>();
        if profiles.len() != required.len() {
            bail!("run references a missing agent profile");
        }
        let max_concurrent = request.max_concurrent.unwrap_or(4);
        let objective = request.objective.clone();
        let coordinator = request.coordinator_profile_id.clone();
        let frozen = workflow_blocking(move || {
            for profile in profiles.values() {
                validate_profile(profile)?;
            }
            let source_sha = git2::Repository::open(&workspace.path)
                .ok()
                .and_then(|repository| {
                    let commit = repository.head().ok()?.peel_to_commit().ok()?;
                    Some(commit.id().to_string())
                });
            if isolation == RunIsolation::Isolated && source_sha.is_none() {
                bail!("isolated runs require a source commit in the workspace");
            }
            let source = RunSourceSnapshot {
                workspace: WorkflowSourceWorkspace {
                    workspace_id: workspace.id,
                    instance_id: workspace.instance_id,
                    project_id: workspace.project_id,
                    path: workspace.path,
                    project_repo_path: project.repo_path,
                },
                source_sha,
            };
            let recipe = match selected {
                Some(selected) => {
                    let recipe = WorkflowRecipeSnapshot::freeze(selected.source, selected.recipe)?;
                    let proposal = WorkflowPlanProposal {
                        objective,
                        source_sha: source.source_sha.clone().unwrap_or_default(),
                        recipe_source: recipe.source.clone(),
                        expected_recipe_digest: recipe.recipe.content_digest()?,
                        coordinator_profile_id: coordinator,
                        role_profiles: role_profiles.clone(),
                        max_concurrent,
                        tasks: Vec::new(),
                    };
                    let bound = profiles
                        .iter()
                        .filter(|(id, _)| {
                            role_profiles.values().any(|value| value == *id)
                                || *id == &proposal.coordinator_profile_id
                        })
                        .map(|(id, profile)| (id.clone(), profile.clone()))
                        .collect();
                    super::run_plan_compilation::validate_selection(&proposal, &recipe, &bound)?;
                    Some(recipe)
                }
                None => None,
            };
            Ok((
                source,
                FrozenRunSelection {
                    recipe,
                    profiles,
                    role_profiles,
                    worker_profile_id: Some(worker),
                },
            ))
        })
        .await?;
        let (source, selection) = frozen;
        let stall_policy = request.stall_policy.clone().unwrap_or_else(|| "ask".into());
        let mut tx = self.pool().begin().await?;
        sqlx::query("UPDATE orchestrationBoardRevision SET revision = revision WHERE id = 1")
            .execute(&mut *tx)
            .await?;
        if let Some(row) = sqlx::query(
            "SELECT request_digest, receipt FROM runCommandReceipts WHERE request_id = ?",
        )
        .bind(&request.request_id)
        .fetch_optional(&mut *tx)
        .await?
        {
            if row.try_get::<String, _>("request_digest")? != digest {
                bail!("run_request_conflict: request id was already used for different contents");
            }
            let receipt: String = row.try_get("receipt")?;
            return Ok((serde_json::from_str(&receipt)?, false));
        }
        let active: Option<String> = sqlx::query_scalar(sqlx::AssertSqlSafe(format!(
            "SELECT id FROM orchestrationCoordinatorRuns WHERE workspace_id = ? AND {} LIMIT 1",
            super::orchestration_run_store::RUN_HOLDS_WORKSPACE_SQL
        )))
        .bind(&request.workspace_id)
        .fetch_optional(&mut *tx)
        .await?;
        if let Some(active) = active {
            bail!("run_workspace_busy: a run is already active in this workspace: {active}");
        }
        let run_id = super::orchestration_message_store::orchestration_id("run");
        let tab_id = reserve_coordinator.then(|| uuid::Uuid::new_v4().to_string());
        let recipe_snapshot = selection
            .recipe
            .as_ref()
            .map(serde_json::to_string)
            .transpose()?;
        let recipe_source_json = recipe_source
            .as_ref()
            .map(serde_json::to_string)
            .transpose()?;
        sqlx::query(
            "INSERT INTO orchestrationCoordinatorRuns
            (id, spec, status, coordinator_handle, workspace_id, max_concurrent, isolation,
             approval_required, stall_policy, recipe_source, recipe_snapshot, profiles_snapshot,
             source_snapshot, coordinator_profile_id, coordinator_tab_id, coordinator_state,
             integration_sha)
            VALUES (?, ?, 'planning', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(&run_id)
        .bind(&request.objective)
        .bind(&tab_id)
        .bind(&request.workspace_id)
        .bind(max_concurrent)
        .bind(isolation.as_str())
        .bind(request.approval_required)
        .bind(&stall_policy)
        .bind(recipe_source_json)
        .bind(recipe_snapshot)
        .bind(serde_json::to_string(&selection)?)
        .bind(serde_json::to_string(&source)?)
        .bind(&request.coordinator_profile_id)
        .bind(&tab_id)
        .bind(if reserve_coordinator {
            "reserved"
        } else {
            "none"
        })
        .bind(match isolation {
            RunIsolation::Isolated => source.source_sha.clone(),
            RunIsolation::Shared => None,
        })
        .execute(&mut *tx)
        .await?;
        let mut created = NewRunEvent::new(&run_id, RunEventKind::Created);
        created.summary = &request.objective;
        created.actor_kind = Some(actor.kind);
        created.actor_id = actor.id.as_deref();
        created.payload = Some(serde_json::json!({
            "isolation": isolation.as_str(),
            "recipe": recipe_source,
            "sourceSha": source.source_sha,
            "approvalRequired": request.approval_required,
        }));
        record_run_event(&mut tx, &created).await?;
        let receipt = RunCreated {
            run_id: run_id.clone(),
            status: "planning".into(),
            isolation,
            coordinator_tab_id: tab_id,
            coordinator_profile_id: request.coordinator_profile_id.clone(),
        };
        sqlx::query(
            "INSERT INTO runCommandReceipts(request_id, request_digest, run_id, receipt)
            VALUES (?, ?, ?, ?)",
        )
        .bind(&request.request_id)
        .bind(&digest)
        .bind(&run_id)
        .bind(serde_json::to_string(&receipt)?)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok((receipt, true))
    }

    /// The coordinator profile and reserved terminal of a planning run.
    pub async fn run_coordinator_launch(
        &self,
        run_id: &str,
    ) -> Result<(AgentProfile, WorkflowCoordinatorReceipt)> {
        let row = sqlx::query(
            "SELECT profiles_snapshot, coordinator_profile_id FROM orchestrationCoordinatorRuns
            WHERE id = ?",
        )
        .bind(run_id)
        .fetch_optional(self.pool())
        .await?
        .ok_or_else(|| anyhow!("run not found: {run_id}"))?;
        let selection: FrozenRunSelection = serde_json::from_str(
            &row.try_get::<Option<String>, _>("profiles_snapshot")?
                .ok_or_else(|| anyhow!("run has no frozen profiles"))?,
        )?;
        let profile_id: String = row
            .try_get::<Option<String>, _>("coordinator_profile_id")?
            .ok_or_else(|| anyhow!("run has no coordinator profile"))?;
        let profile = selection
            .profiles
            .get(&profile_id)
            .cloned()
            .ok_or_else(|| anyhow!("run coordinator profile is unavailable"))?;
        let receipt = self
            .workflow_coordinator(run_id)
            .await?
            .ok_or_else(|| anyhow!("run has no coordinator terminal"))?;
        Ok((profile, receipt))
    }

    /// The agent type of a run's worker profile, frozen when it was created.
    pub async fn run_worker_agent_type(&self, run_id: &str) -> Result<Option<String>> {
        let raw: Option<Option<String>> = sqlx::query_scalar(
            "SELECT profiles_snapshot FROM orchestrationCoordinatorRuns WHERE id = ?",
        )
        .bind(run_id)
        .fetch_optional(self.pool())
        .await?;
        let Some(raw) = raw.flatten() else {
            return Ok(None);
        };
        let selection: FrozenRunSelection = serde_json::from_str(&raw)?;
        Ok(selection
            .worker_profile_id
            .as_ref()
            .and_then(|id| selection.profiles.get(id))
            .map(|profile| profile.agent_type.clone()))
    }

    /// A stored receipt for `request_id`, or an error when the id was used
    /// for different contents.
    pub(super) async fn run_command_receipt(
        &self,
        request_id: &str,
        digest: &str,
    ) -> Result<Option<serde_json::Value>> {
        let Some(row) = sqlx::query(
            "SELECT request_digest, receipt FROM runCommandReceipts WHERE request_id = ?",
        )
        .bind(request_id)
        .fetch_optional(self.pool())
        .await?
        else {
            return Ok(None);
        };
        if row.try_get::<String, _>("request_digest")? != digest {
            bail!("run_request_conflict: request id was already used for different contents");
        }
        Ok(Some(serde_json::from_str(
            &row.try_get::<String, _>("receipt")?,
        )?))
    }
}

pub(super) fn portable_request_id(id: &str) -> Result<()> {
    workflow_text(id, 160)?;
    if !id
        .bytes()
        .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b':' | b'.'))
    {
        bail!("requestId must be a portable identifier");
    }
    Ok(())
}

fn validate_create(request: &CreateRun) -> Result<()> {
    portable_request_id(&request.request_id)?;
    workflow_text(&request.workspace_id, 160)?;
    workflow_text(&request.objective, 16384)?;
    workflow_text(&request.coordinator_profile_id, 160)?;
    if let Some(policy) = &request.stall_policy {
        if !RUN_STALL_POLICIES.contains(&policy.as_str()) {
            bail!(
                "stallPolicy must be one of {}",
                RUN_STALL_POLICIES.join(", ")
            );
        }
    }
    if request
        .max_concurrent
        .is_some_and(|value| !(1..=16).contains(&value))
    {
        bail!("maxConcurrent must be between 1 and 16");
    }
    if request.role_profiles.len() > 32 {
        bail!("too many role profile bindings");
    }
    Ok(())
}
