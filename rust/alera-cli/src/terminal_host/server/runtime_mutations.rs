use std::sync::Arc;

use alera_core::runtime::RuntimeStore;
use serde_json::{json, Value};
use tokio::sync::Mutex;

use crate::hosted_review_retention;
use crate::managed_workspace::{remove_managed_workspace, ManagedWorkspaceRemoveRequest};
use crate::terminal_host::emulator::EmulatorManager;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::MOBILE_EMULATOR_TAB_KIND;

use super::codex_requests::CodexCleanupPlan;
use super::codex_runtime_cleanup::CodexCleanupEntry;

#[path = "runtime_mutation_emulator_cleanup.rs"]
mod emulator_cleanup;
use emulator_cleanup::{close_tab, close_workspace, close_workspaces};

#[path = "runtime_mutation_hosted_review_retention.rs"]
mod hosted_review_retentions;
#[cfg(test)]
mod tests;

#[derive(Clone)]
pub(crate) enum RuntimeMutationRequest {
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
}

pub(crate) struct RuntimeMutationOutcome {
    pub(crate) result: HostResult<RuntimeMutationCompletion>,
    pub(super) pending_codex_cleanup: Vec<CodexCleanupEntry>,
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
    emulators: Option<Arc<Mutex<EmulatorManager>>>,
    runtime_store: RuntimeStore,
    request: RuntimeMutationRequest,
    codex_cleanup: Option<CodexCleanupPlan>,
) -> RuntimeMutationOutcome {
    let hosted_review_retentions =
        hosted_review_retentions::for_request(&runtime_store, &request).await;
    let mut prepared_codex_cleanup = if let Some(cleanup) = codex_cleanup {
        match cleanup.prepare().await {
            Ok(prepared) => Some(prepared),
            Err(error) => {
                return RuntimeMutationOutcome {
                    result: Err(error),
                    pending_codex_cleanup: Vec::new(),
                    ended_pointer_tab_ids: Vec::new(),
                    closed_session_tab_ids: Vec::new(),
                    committed_tab_ids: Vec::new(),
                    effect_on_error: None,
                    stopped_workspace_tab_ids: Vec::new(),
                    pending_workspace_shutdown: None,
                };
            }
        }
    } else {
        None
    };
    let mut manager = match emulators {
        Some(manager) => Some(manager.lock_owned().await),
        None => None,
    };
    let mut ended_pointer_tab_ids = Vec::new();
    let mut closed_session_tab_ids = Vec::new();
    let mut committed_tab_ids = Vec::new();
    let mut effect_on_error = None;
    let result = async {
        match request {
            RuntimeMutationRequest::RemoveProject { project_id } => {
                let workspace_ids = workspace_ids_for_project(&runtime_store, &project_id).await?;
                let closed_tab_ids = emulator_tab_ids_for_workspaces(
                    &runtime_store,
                    manager.as_deref(),
                    &workspace_ids,
                )
                .await?;
                close_workspaces(
                    manager.as_deref_mut(),
                    &workspace_ids,
                    &mut ended_pointer_tab_ids,
                    &mut closed_session_tab_ids,
                )
                .await?;
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
                    closed_tab_ids,
                })
            }
            RuntimeMutationRequest::RemoveWorkspace {
                workspace_id,
                cascade_tabs,
            } => {
                let closed_tab_ids = emulator_tab_ids_for_workspace(
                    &runtime_store,
                    manager.as_deref(),
                    &workspace_id,
                )
                .await?;
                close_workspace(
                    manager.as_deref_mut(),
                    &workspace_id,
                    &mut ended_pointer_tab_ids,
                    &mut closed_session_tab_ids,
                )
                .await?;
                runtime_store
                    .remove_workspace(&workspace_id, cascade_tabs)
                    .await
                    .map_err(runtime_store_error)?;
                Ok(RuntimeMutationCompletion {
                    response: json!({}),
                    effect: RuntimeMutationEffect::WorkspaceRemoved { workspace_id },
                    closed_tab_ids,
                })
            }
            RuntimeMutationRequest::RemoveProjectWorkspaces { project_id } => {
                let workspace_ids = workspace_ids_for_project(&runtime_store, &project_id).await?;
                let closed_tab_ids = emulator_tab_ids_for_workspaces(
                    &runtime_store,
                    manager.as_deref(),
                    &workspace_ids,
                )
                .await?;
                close_workspaces(
                    manager.as_deref_mut(),
                    &workspace_ids,
                    &mut ended_pointer_tab_ids,
                    &mut closed_session_tab_ids,
                )
                .await?;
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
                    closed_tab_ids,
                })
            }
            RuntimeMutationRequest::RemoveManagedWorkspace { request } => {
                let workspace_id = request.id.clone();
                let closed_tab_ids = emulator_tab_ids_for_workspace(
                    &runtime_store,
                    manager.as_deref(),
                    &workspace_id,
                )
                .await?;
                close_workspace(
                    manager.as_deref_mut(),
                    &workspace_id,
                    &mut ended_pointer_tab_ids,
                    &mut closed_session_tab_ids,
                )
                .await?;
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
                    closed_tab_ids,
                })
            }
            RuntimeMutationRequest::RemoveTab { tab_id } => {
                let (workspace_id, closed_tab_ids) =
                    tab_removal_context(&runtime_store, manager.as_deref(), &tab_id).await?;
                close_tab(
                    manager.as_deref_mut(),
                    &tab_id,
                    &mut ended_pointer_tab_ids,
                    &mut closed_session_tab_ids,
                )
                .await?;
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
                    closed_tab_ids,
                })
            }
            RuntimeMutationRequest::RemoveWorkspaceTabs { workspace_id } => {
                let closed_tab_ids = emulator_tab_ids_for_workspace(
                    &runtime_store,
                    manager.as_deref(),
                    &workspace_id,
                )
                .await?;
                close_workspace(
                    manager.as_deref_mut(),
                    &workspace_id,
                    &mut ended_pointer_tab_ids,
                    &mut closed_session_tab_ids,
                )
                .await?;
                runtime_store
                    .sleep_workspace(&workspace_id)
                    .await
                    .map_err(runtime_store_error)?;
                Ok(RuntimeMutationCompletion {
                    response: json!({}),
                    effect: RuntimeMutationEffect::WorkspaceTabsRemoved { workspace_id },
                    closed_tab_ids,
                })
            }
            RuntimeMutationRequest::SleepWorkspace { workspace_id } => {
                let closed_tab_ids = emulator_tab_ids_for_workspace(
                    &runtime_store,
                    manager.as_deref(),
                    &workspace_id,
                )
                .await?;
                close_workspace(
                    manager.as_deref_mut(),
                    &workspace_id,
                    &mut ended_pointer_tab_ids,
                    &mut closed_session_tab_ids,
                )
                .await?;
                runtime_store
                    .sleep_workspace(&workspace_id)
                    .await
                    .map_err(runtime_store_error)?;
                committed_tab_ids = closed_tab_ids.clone();
                effect_on_error = Some(RuntimeMutationEffect::WorkspaceSlept {
                    workspace_id: workspace_id.clone(),
                });
                record_sleep_activity(&runtime_store, &workspace_id).await?;
                Ok(RuntimeMutationCompletion {
                    response: json!({}),
                    effect: RuntimeMutationEffect::WorkspaceSlept { workspace_id },
                    closed_tab_ids,
                })
            }
        }
    }
    .await;
    ended_pointer_tab_ids.sort_unstable();
    ended_pointer_tab_ids.dedup();
    closed_session_tab_ids.sort_unstable();
    closed_session_tab_ids.dedup();
    if result.is_ok() {
        if let Some(cleanup) = prepared_codex_cleanup.as_mut() {
            // The store mutation is the acknowledgement boundary. Codex can
            // take up to its request timeout to delete a thread, and that
            // best-effort cleanup must not hold tab removal responses open.
            cleanup.delete_threads_after_commit();
        }
    }
    if result.is_ok() || effect_on_error.is_some() {
        hosted_review_retention::release(hosted_review_retentions);
    }
    let pending_codex_cleanup = prepared_codex_cleanup
        .map(|cleanup| cleanup.into_entries())
        .unwrap_or_default();
    RuntimeMutationOutcome {
        result,
        pending_codex_cleanup,
        ended_pointer_tab_ids,
        closed_session_tab_ids,
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

async fn tab_removal_context(
    runtime_store: &RuntimeStore,
    manager: Option<&EmulatorManager>,
    tab_id: &str,
) -> HostResult<(Option<String>, Vec<String>)> {
    let tab = runtime_store
        .find_workspace_tab(tab_id)
        .await
        .map_err(runtime_store_error)?;
    let workspace_id = tab.as_ref().map(|tab| tab.workspace_id.clone());
    let is_emulator_tab = tab
        .as_ref()
        .is_some_and(|tab| tab.kind == MOBILE_EMULATOR_TAB_KIND)
        || manager.is_some_and(|manager| manager.contains(tab_id));
    let closed_tab_ids = if is_emulator_tab {
        vec![tab_id.to_string()]
    } else {
        Vec::new()
    };
    Ok((workspace_id, closed_tab_ids))
}

async fn emulator_tab_ids_for_workspaces(
    runtime_store: &RuntimeStore,
    manager: Option<&EmulatorManager>,
    workspace_ids: &[String],
) -> HostResult<Vec<String>> {
    let mut tab_ids = Vec::new();
    for workspace_id in workspace_ids {
        tab_ids.extend(emulator_tab_ids_for_workspace(runtime_store, manager, workspace_id).await?);
    }
    tab_ids.sort_unstable();
    tab_ids.dedup();
    Ok(tab_ids)
}

async fn emulator_tab_ids_for_workspace(
    runtime_store: &RuntimeStore,
    manager: Option<&EmulatorManager>,
    workspace_id: &str,
) -> HostResult<Vec<String>> {
    let mut tab_ids: Vec<String> = runtime_store
        .list_workspace_tabs(workspace_id)
        .await
        .map_err(runtime_store_error)?
        .into_iter()
        .filter(|tab| tab.kind == MOBILE_EMULATOR_TAB_KIND)
        .map(|tab| tab.id)
        .collect();
    if let Some(manager) = manager {
        tab_ids.extend(manager.tab_ids_for_workspace(workspace_id));
    }
    tab_ids.sort_unstable();
    tab_ids.dedup();
    Ok(tab_ids)
}

fn runtime_store_error(error: impl std::fmt::Display) -> HostError {
    HostError::state(error.to_string())
}
