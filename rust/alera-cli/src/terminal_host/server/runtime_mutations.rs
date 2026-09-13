use alera_core::runtime::RuntimeStore;
use serde_json::{json, Value};

use crate::hosted_review_retention;
use crate::managed_workspace::{remove_managed_workspace, ManagedWorkspaceRemoveRequest};
use crate::managed_workspace_handoff::{
    ManagedWorkspaceHandOffRequest, ManagedWorkspaceHandOnRequest,
};
use crate::terminal_host::host_error::{HostError, HostResult};

#[path = "runtime_mutation_hosted_review_retention.rs"]
mod hosted_review_retentions;
#[path = "runtime_remote_workspace_relocation.rs"]
mod remote_workspace_relocation;
#[cfg(test)]
mod tests;
#[path = "runtime_workspace_relocation.rs"]
mod workspace_relocation;

#[derive(Clone)]
pub(crate) enum RuntimeMutationRequest {
    RecoverRelocationSetup {
        workspace_id: String,
        relocation_id: String,
        attempt_id: String,
    },
    PrepareRelocationSetup {
        workspace_id: String,
        relocation_id: String,
        directory: std::path::PathBuf,
    },
    RunRelocationSetup {
        workspace_id: String,
        relocation_id: String,
    },
    RemoveProject {
        project_id: String,
    },
    RemoveWorkspace {
        workspace_id: String,
        cascade_tabs: bool,
    },
    RemoveProjectWorkspaces {
        project_id: String,
    },
    RemoveManagedWorkspace {
        request: ManagedWorkspaceRemoveRequest,
    },
    RemoveSharedWorkspace {
        remote_automation_cleanup: Option<Box<alera_core::runtime::RemoteAutomationCleanup>>,
        automation_cleanup: Option<Box<alera_core::runtime::AutomationRun>>,
        request: ManagedWorkspaceRemoveRequest,
        buffer_guard: super::checkout_buffer_guard_claims::CheckoutBufferGuardProof,
        remote_retirement: Option<crate::remote_shared_retirement::RemoteRetirementProof>,
    },
    HandOnWorkspace {
        request: ManagedWorkspaceHandOnRequest,
        buffer_guard: super::checkout_buffer_guard_claims::CheckoutBufferGuardProof,
    },
    HandOffWorkspace {
        request: ManagedWorkspaceHandOffRequest,
        move_changes: bool,
        replacement_branch: Option<String>,
        buffer_guard: super::checkout_buffer_guard_claims::CheckoutBufferGuardProof,
    },
    RemoveTab {
        tab_id: String,
    },
    RemoveWorkspaceTabs {
        workspace_id: String,
    },
    SleepWorkspace {
        workspace_id: String,
    },
}

pub(crate) struct RuntimeMutationCompletion {
    pub(super) response: Value,
    pub(super) effect: RuntimeMutationEffect,
    pub(super) closed_tab_ids: Vec<String>,
    pub(super) hand_on_relocate: Option<Box<HandOnSessionRelocate>>,
}

pub(super) struct HandOnSessionRelocate {
    pub source_workspace_id: String,
    pub destination_workspace_id: String,
    pub source_path: String,
    pub dest_path: String,
}

pub(crate) struct RuntimeMutationOutcome {
    pub(crate) result: HostResult<RuntimeMutationCompletion>,
    pub(super) ended_pointer_tab_ids: Vec<String>,
    pub(super) closed_session_tab_ids: Vec<String>,
    pub(super) committed_tab_ids: Vec<String>,
    pub(super) effect_on_error: Option<RuntimeMutationEffect>,
    pub(super) stopped_workspace_tab_ids: Vec<String>,
    pub(super) pending_workspace_shutdown: Option<
        Box<(
            String,
            crate::terminal_host::session::workspace_shutdown::WorkspaceShutdown,
        )>,
    >,
}

pub(crate) struct RuntimeMutationFinished {
    pub(crate) client_id: u64,
    pub(crate) request_id: i64,
    pub(crate) outcome: RuntimeMutationOutcome,
}

pub(super) enum RuntimeMutationEffect {
    SetupFinished,
    ProjectRemoved {
        project_id: String,
        workspace_ids: Vec<String>,
    },
    WorkspaceRemoved {
        workspace_id: String,
    },
    ProjectWorkspacesRemoved {
        project_id: String,
        workspace_ids: Vec<String>,
    },
    ManagedWorkspaceRemoved {
        project_id: String,
        workspace_id: String,
    },
    WorkspaceRelocated {
        project_id: String,
        workspace_id: String,
        source_path: String,
    },
    TabRemoved {
        tab_id: String,
        workspace_id: Option<String>,
    },
    WorkspaceTabsRemoved {
        workspace_id: String,
    },
    WorkspaceSlept {
        workspace_id: String,
    },
}

pub(super) async fn run_runtime_mutation(
    runtime_store: RuntimeStore,
    request: RuntimeMutationRequest,
) -> RuntimeMutationOutcome {
    let hosted_review_retentions =
        hosted_review_retentions::for_request(&runtime_store, &request).await;
    let committed_tab_ids = Vec::new();
    let mut effect_on_error = None;
    let result = async {
        match request {
            RuntimeMutationRequest::RecoverRelocationSetup { workspace_id, relocation_id, attempt_id } => {
                let report = crate::workspace_relocation_recovery::recover(&runtime_store, &workspace_id, &relocation_id, &attempt_id).await.map_err(runtime_store_error)?;
                Ok(RuntimeMutationCompletion { response: serde_json::to_value(report).map_err(runtime_store_error)?, effect: RuntimeMutationEffect::SetupFinished, closed_tab_ids: Vec::new(), hand_on_relocate: None })
            }
            RuntimeMutationRequest::PrepareRelocationSetup { workspace_id, relocation_id, directory } => {
                let workspace = runtime_store.find_workspace(&workspace_id).await.map_err(runtime_store_error)?.ok_or_else(|| HostError::state("Workspace no longer exists"))?;
                let (setup_report, deferred_setup_command) = crate::workspace_relocation_setup::prepare_launcher(&runtime_store, &workspace, &relocation_id, &directory).await.map_err(runtime_store_error)?;
                Ok(RuntimeMutationCompletion { response: json!({"setupReport": setup_report, "deferredSetupCommand": deferred_setup_command, "relocationId": relocation_id}), effect: RuntimeMutationEffect::SetupFinished, closed_tab_ids: Vec::new(), hand_on_relocate: None })
            }
            RuntimeMutationRequest::RunRelocationSetup { workspace_id, relocation_id } => {
                let report = crate::workspace_relocation_setup::run(&runtime_store, &workspace_id, &relocation_id).await.map_err(runtime_store_error)?;
                Ok(RuntimeMutationCompletion { response: serde_json::to_value(report).map_err(runtime_store_error)?, effect: RuntimeMutationEffect::SetupFinished, closed_tab_ids: Vec::new(), hand_on_relocate: None })
            }
            RuntimeMutationRequest::RemoveProject { project_id } => {
                let workspace_ids = workspace_ids_for_project(&runtime_store, &project_id).await?;
                runtime_store
                    .remove_project(&project_id)
                    .await
                    .map_err(runtime_store_error)?;
                Ok(RuntimeMutationCompletion {
                    response: json!({}),
                    effect: RuntimeMutationEffect::ProjectRemoved {
                        project_id,
                        workspace_ids,
                    },
                    closed_tab_ids: Vec::new(),
                    hand_on_relocate: None,
                })
            }
            RuntimeMutationRequest::RemoveWorkspace {
                workspace_id,
                cascade_tabs,
            } => {
                runtime_store
                    .remove_workspace(&workspace_id, cascade_tabs)
                    .await
                    .map_err(runtime_store_error)?;
                Ok(RuntimeMutationCompletion {
                    response: json!({}),
                    effect: RuntimeMutationEffect::WorkspaceRemoved { workspace_id },
                    closed_tab_ids: Vec::new(),
                    hand_on_relocate: None,
                })
            }
            RuntimeMutationRequest::RemoveProjectWorkspaces { project_id } => {
                let workspace_ids = workspace_ids_for_project(&runtime_store, &project_id).await?;
                runtime_store
                    .remove_workspaces_for_project(&project_id)
                    .await
                    .map_err(runtime_store_error)?;
                Ok(RuntimeMutationCompletion {
                    response: json!({}),
                    effect: RuntimeMutationEffect::ProjectWorkspacesRemoved {
                        project_id,
                        workspace_ids,
                    },
                    closed_tab_ids: Vec::new(),
                    hand_on_relocate: None,
                })
            }
            RuntimeMutationRequest::RemoveSharedWorkspace {
                remote_automation_cleanup,
                automation_cleanup,
                request,
                buffer_guard,
                remote_retirement,
            } => {
                buffer_guard.verify()?;
                let workspace = if let Some(scope) = remote_automation_cleanup {
                    let workspace = crate::shared_workspace_removal::validate_shared_workspace_removal(&runtime_store, &request).await.map_err(runtime_store_error)?;
                    buffer_guard.verify_workspace(&workspace)?;
                    runtime_store.retire_verified_remote_automation_workspace(&scope, &workspace).await.map_err(runtime_store_error)?;
                    workspace
                } else if let Some(run) = automation_cleanup {
                    let workspace = crate::shared_workspace_removal::validate_shared_workspace_removal(&runtime_store, &request).await.map_err(runtime_store_error)?;
                    buffer_guard.verify_workspace(&workspace)?;
                    if workspace.host_id != alera_core::runtime::LOCAL_HOST_ID {
                        remote_retirement.as_ref().ok_or_else(|| HostError::state("Automatic SSH cleanup requires a verified owner retirement receipt"))?.verify(&workspace).map_err(runtime_store_error)?;
                    }
                    runtime_store.retire_verified_automation_shared_workspace(&run, &workspace).await.map_err(runtime_store_error)?;
                    workspace
                } else { match remote_retirement {
                    Some(proof) => crate::shared_workspace_removal::remove_after_remote_retirement(&runtime_store, &request, &proof).await,
                    None => crate::shared_workspace_removal::remove_shared_workspace(&runtime_store, &request).await,
                }.map_err(runtime_store_error)? };
                Ok(RuntimeMutationCompletion {
                    response: serde_json::to_value(&workspace).map_err(runtime_store_error)?,
                    effect: RuntimeMutationEffect::ManagedWorkspaceRemoved {
                        project_id: workspace.project_id,
                        workspace_id: workspace.id,
                    },
                    closed_tab_ids: Vec::new(),
                    hand_on_relocate: None,
                })
            }
            RuntimeMutationRequest::RemoveManagedWorkspace { request } => {
                let workspace_id = request.id.clone();
                let workspace = remove_managed_workspace(&runtime_store, request)
                    .await
                    .map_err(runtime_store_error)?;
                let project_id = workspace.project_id.clone();
                Ok(RuntimeMutationCompletion {
                    response: serde_json::to_value(workspace).map_err(runtime_store_error)?,
                    effect: RuntimeMutationEffect::ManagedWorkspaceRemoved {
                        project_id,
                        workspace_id,
                    },
                    closed_tab_ids: Vec::new(),
                    hand_on_relocate: None,
                })
            }
            RuntimeMutationRequest::HandOffWorkspace { request, move_changes, replacement_branch, buffer_guard } => {
                buffer_guard.verify()?;
                if buffer_guard.is_remote() {
                    if request.reuse_existing_branch != replacement_branch.is_some() {
                        return Err(HostError::state("Moving the current branch requires an explicit replacement branch"));
                    }
                    let workspace = runtime_store.find_workspace(&request.id).await.map_err(runtime_store_error)?.ok_or_else(|| HostError::state("Workspace no longer exists"))?;
                    if request.name.as_deref().map(str::trim).is_some_and(|name| !name.is_empty() && name != workspace.name) {
                        return Err(HostError::state("Hand Off preserves the task name. Rename it separately."));
                    }
                    return remote_workspace_relocation::run(&runtime_store, alera_core::runtime::WorkspaceRelocationIntent {
                        workspace_id: request.id, to_project_checkout: false, destination_path: request.path,
                        branch: Some(request.branch), replacement_branch, move_changes, shared_impact_confirmed: true,
                    }, request.relocation_id, request.workspace_root, &buffer_guard).await.map_err(runtime_store_error);
                }
                let journal = workspace_relocation::prepare_hand_off(&runtime_store, &request, move_changes, replacement_branch).await.map_err(runtime_store_error)?;
                effect_on_error = Some(RuntimeMutationEffect::WorkspaceRelocated {
                    project_id: journal.source.project_id.clone(), workspace_id: journal.source.id.clone(), source_path: journal.source.path.clone(),
                });
                let project = runtime_store.find_project(&journal.source.project_id).await.map_err(runtime_store_error)?.ok_or_else(|| HostError::state("Project disappeared before relocation"))?;
                crate::workspace_relocation_setup::prepare(&runtime_store, &project, &journal.id).await.map_err(runtime_store_error)?;
                let workspace = runtime_store.resume_local_workspace_relocation(&journal.id, || buffer_guard.verify().map_err(|error| anyhow::anyhow!(error.wire_message()))).await.map_err(runtime_store_error)?;
                let (setup_report, deferred_setup_command) = if request.defer_setup {
                    crate::workspace_relocation_setup::defer(&runtime_store, &workspace, &journal.id, request.setup_script_directory.as_deref()).await.map_err(runtime_store_error)?
                } else {
                    (crate::workspace_relocation_setup::run(&runtime_store, &workspace.id, &journal.id).await.map_err(runtime_store_error)?, None)
                };
                let effect = RuntimeMutationEffect::WorkspaceRelocated { project_id: workspace.project_id.clone(), workspace_id: workspace.id.clone(), source_path: journal.source.path };
                let mut response = serde_json::to_value(alera_core::runtime::WorkspaceCreationResult { workspace, setup_report, deferred_setup_command }).map_err(runtime_store_error)?;
                response["relocationId"] = json!(journal.id);
                Ok(RuntimeMutationCompletion {
                    response,
                    effect, closed_tab_ids: Vec::new(), hand_on_relocate: None,
                })
            }
            RuntimeMutationRequest::HandOnWorkspace { request, buffer_guard } => {
                let workspace_id = request.id.clone();
                buffer_guard.verify()?;
                if buffer_guard.is_remote() {
                    return remote_workspace_relocation::run(&runtime_store, alera_core::runtime::WorkspaceRelocationIntent {
                        workspace_id, to_project_checkout: true, destination_path: None, branch: None,
                        replacement_branch: None, move_changes: true, shared_impact_confirmed: true,
                    }, request.relocation_id, None, &buffer_guard).await.map_err(runtime_store_error);
                }
                let journal = runtime_store.prepare_local_workspace_relocation_with_id(alera_core::runtime::WorkspaceRelocationIntent {
                    workspace_id: workspace_id.clone(), to_project_checkout: true,
                    destination_path: None, branch: None, replacement_branch: None,
                    move_changes: true, shared_impact_confirmed: true,
                }, request.relocation_id.clone()).await.map_err(runtime_store_error)?;
                effect_on_error = Some(RuntimeMutationEffect::WorkspaceRelocated {
                    project_id: journal.source.project_id.clone(),
                    workspace_id: workspace_id.clone(),
                    source_path: journal.source.path.clone(),
                });
                let workspace = runtime_store.resume_local_workspace_relocation(&journal.id, || {
                    buffer_guard.verify().map_err(|error| anyhow::anyhow!(error.wire_message()))
                }).await.map_err(runtime_store_error)?;
                let project_id = workspace.project_id.clone();
                Ok(RuntimeMutationCompletion {
                    response: json!({"workspace": workspace, "removedWorkspaceId": null, "recoveryStashOid": runtime_store.find_workspace_relocation(&journal.id).await.map_err(runtime_store_error)?.and_then(|journal| journal.recovery_stash_oid), "relocationId": journal.id}),
                    effect: RuntimeMutationEffect::WorkspaceRelocated {
                        project_id,
                        workspace_id,
                        source_path: journal.source.path,
                    },
                    closed_tab_ids: Vec::new(),
                    hand_on_relocate: None,
                })
            }
            RuntimeMutationRequest::RemoveTab { tab_id } => {
                let workspace_id = runtime_store
                    .find_workspace_tab(&tab_id)
                    .await
                    .map_err(runtime_store_error)?
                    .map(|tab| tab.workspace_id);
                runtime_store
                    .remove_workspace_tab(&tab_id)
                    .await
                    .map_err(runtime_store_error)?;
                Ok(RuntimeMutationCompletion {
                    response: json!({}),
                    effect: RuntimeMutationEffect::TabRemoved {
                        tab_id,
                        workspace_id,
                    },
                    closed_tab_ids: Vec::new(),
                    hand_on_relocate: None,
                })
            }
            RuntimeMutationRequest::RemoveWorkspaceTabs { workspace_id } => {
                runtime_store
                    .sleep_workspace(&workspace_id)
                    .await
                    .map_err(runtime_store_error)?;
                Ok(RuntimeMutationCompletion {
                    response: json!({}),
                    effect: RuntimeMutationEffect::WorkspaceTabsRemoved { workspace_id },
                    closed_tab_ids: Vec::new(),
                    hand_on_relocate: None,
                })
            }
            RuntimeMutationRequest::SleepWorkspace { workspace_id } => {
                runtime_store
                    .sleep_workspace(&workspace_id)
                    .await
                    .map_err(runtime_store_error)?;
                effect_on_error = Some(RuntimeMutationEffect::WorkspaceSlept {
                    workspace_id: workspace_id.clone(),
                });
                record_sleep_activity(&runtime_store, &workspace_id).await?;
                Ok(RuntimeMutationCompletion {
                    response: json!({}),
                    effect: RuntimeMutationEffect::WorkspaceSlept { workspace_id },
                    closed_tab_ids: Vec::new(),
                    hand_on_relocate: None,
                })
            }
        }
    }
    .await;
    if result.is_ok() || effect_on_error.is_some() {
        hosted_review_retention::release(hosted_review_retentions);
    }
    RuntimeMutationOutcome {
        result,
        ended_pointer_tab_ids: Vec::new(),
        closed_session_tab_ids: Vec::new(),
        committed_tab_ids,
        effect_on_error,
        stopped_workspace_tab_ids: Vec::new(),
        pending_workspace_shutdown: None,
    }
}

async fn record_sleep_activity(runtime_store: &RuntimeStore, workspace_id: &str) -> HostResult<()> {
    #[cfg(test)]
    if workspace_id == "force-activity-failure" {
        return Err(HostError::state("forced workspace activity failure"));
    }
    runtime_store
        .record_workspace_activity(workspace_id, chrono::Utc::now())
        .await
        .map_err(runtime_store_error)
}

async fn workspace_ids_for_project(
    runtime_store: &RuntimeStore,
    project_id: &str,
) -> HostResult<Vec<String>> {
    Ok(runtime_store
        .list_workspaces(project_id)
        .await
        .map_err(runtime_store_error)?
        .into_iter()
        .map(|workspace| workspace.id)
        .collect())
}

fn runtime_store_error(error: impl std::fmt::Display) -> HostError {
    HostError::state(error.to_string())
}
