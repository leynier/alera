use std::path::PathBuf;

use async_trait::async_trait;

use alera_core::runtime::{
    ChatOrchestrationNewWorkspace, ChatOrchestrationSetupMode, ChatOrchestrationWorkspaceMode,
    RuntimeStore,
};

use crate::terminal_host::host_error::{HostError, HostResult};

/// Information returned by the host's managed-workspace layer. A remote host
/// is authoritative for the returned workspace id; the local server never
/// invents a replacement when the target host is unavailable.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ResolvedChatTarget {
    pub workspace_id: String,
    pub project_id: Option<String>,
    pub host_id: String,
}

/// The server owns workspace.createManaged/createShared and host-link
/// routing. The orchestration service calls this boundary after validating a
/// target, so it cannot accidentally use a plain git command or navigate the
/// user's selected workspace.
#[async_trait]
pub(crate) trait ChatTargetResolver: Send + Sync + 'static {
    async fn resolve_existing_chat(&self, chat_id: &str) -> HostResult<ResolvedChatTarget>;

    async fn resolve_existing_workspace(
        &self,
        workspace_id: &str,
    ) -> HostResult<ResolvedChatTarget>;

    async fn create_workspace(
        &self,
        spec: &ChatOrchestrationNewWorkspace,
    ) -> HostResult<ResolvedChatTarget>;
}

/// Resolves targets that already belong to this host. Workspace creation is
/// intentionally left to the host workspace pipeline because it owns branch,
/// setup and remote-link policy; silently inserting a row here would create a
/// chat in a workspace that has never been checked out.
#[derive(Clone)]
pub(crate) struct RuntimeTargetResolver {
    store: RuntimeStore,
    setup_script_directory: Option<PathBuf>,
}

impl RuntimeTargetResolver {
    pub(crate) fn new(store: RuntimeStore) -> Self {
        Self {
            store,
            setup_script_directory: None,
        }
    }

    pub(crate) fn with_setup_script_directory(mut self, directory: PathBuf) -> Self {
        self.setup_script_directory = Some(directory);
        self
    }
}

#[async_trait]
impl ChatTargetResolver for RuntimeTargetResolver {
    async fn resolve_existing_chat(&self, chat_id: &str) -> HostResult<ResolvedChatTarget> {
        let chat = self
            .store
            .agent_chat(chat_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| {
                HostError::conflict("chat_not_found", "Chat not found.", serde_json::json!({}))
            })?;
        self.resolve_existing_workspace(&chat.workspace_id).await
    }

    async fn resolve_existing_workspace(
        &self,
        workspace_id: &str,
    ) -> HostResult<ResolvedChatTarget> {
        let workspace = self
            .store
            .find_workspace(workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| {
                HostError::conflict(
                    "workspace_not_found",
                    "Workspace not found.",
                    serde_json::json!({}),
                )
            })?;
        Ok(ResolvedChatTarget {
            workspace_id: workspace.id,
            project_id: Some(workspace.project_id),
            host_id: workspace.host_id,
        })
    }

    async fn create_workspace(
        &self,
        spec: &ChatOrchestrationNewWorkspace,
    ) -> HostResult<ResolvedChatTarget> {
        if spec.host_id.trim().is_empty() {
            return Err(HostError::format("hostId is required for a new workspace"));
        }
        let workspace = match spec.mode {
            ChatOrchestrationWorkspaceMode::Worktree => {
                let branch = spec
                    .branch
                    .clone()
                    .ok_or_else(|| HostError::format("branch is required for a worktree target"))?;
                let result = crate::managed_workspace::create_managed_workspace(
                    &self.store,
                    crate::managed_workspace::ManagedWorkspaceCreateRequest {
                        id: None,
                        project_id: spec.project_id.clone(),
                        name: spec.name.clone(),
                        branch,
                        source_branch: spec.source_branch.clone(),
                        reuse_existing_branch: spec.reuse_existing_branch.unwrap_or(false),
                        workspace_root: None,
                        path: None,
                        parent_workspace_id: spec.parent_workspace_id.clone(),
                        host_id: Some(spec.host_id.clone()),
                        defer_setup: spec.setup == ChatOrchestrationSetupMode::Deferred,
                        skip_setup: false,
                        setup_script_directory: self.setup_script_directory.clone(),
                    },
                )
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
                result.workspace
            }
            ChatOrchestrationWorkspaceMode::Shared => {
                crate::shared_workspace::create_shared_workspace(
                    &self.store,
                    crate::shared_workspace::SharedWorkspaceCreateRequest {
                        project_id: spec.project_id.clone(),
                        id: None,
                        name: spec.name.clone(),
                        host_id: Some(spec.host_id.clone()),
                        parent_workspace_id: spec.parent_workspace_id.clone(),
                    },
                )
                .await
                .map_err(|error| HostError::state(error.to_string()))?
                .workspace
            }
        };
        Ok(ResolvedChatTarget {
            workspace_id: workspace.id,
            project_id: Some(workspace.project_id),
            host_id: workspace.host_id,
        })
    }
}
