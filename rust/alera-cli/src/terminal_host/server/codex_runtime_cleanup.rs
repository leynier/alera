use std::collections::HashSet;

use alera_core::runtime::{RuntimeStore, Workspace, WorkspaceTabRecord};
use serde_json::json;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::codex_app_server::CodexAppServer;
use super::codex_requests::codex_thread_sessions::path_matches;
use super::codex_state::{active_turn_id, is_codex_tab, persist_snapshot, snapshot, tab_thread_id};
use super::codex_tab_lifecycle::{
    active_cwd, clear_stale_thread_activity, set_active_cwd, thread_owned_by_alera,
};
use super::ServerActor;

pub(crate) struct CodexCleanupPlan {
    pub(super) server: Option<CodexAppServer>,
    pub(super) fallback_cwd: Option<String>,
    pub(super) entries: Vec<CodexCleanupEntry>,
}

pub(super) struct CodexCleanupEntry {
    pub(super) tab_id: String,
    pub(super) thread_id: Option<String>,
    pub(super) turn_id: Option<String>,
    pub(super) delete_thread: bool,
    pub(super) replacement_cwd: Option<String>,
}

impl CodexCleanupPlan {
    pub(crate) async fn execute(self) -> HostResult<Vec<CodexCleanupEntry>> {
        let mut cleanup_receiver = None;
        let needs_server = self
            .entries
            .iter()
            .any(|entry| entry.turn_id.is_some() || entry.delete_thread);
        let server = match (self.server, needs_server) {
            (Some(server), _) => Some(server),
            (None, true) => {
                let cwd = self.fallback_cwd.as_deref().ok_or_else(|| {
                    HostError::state("The Codex workspace is unavailable for cleanup.")
                })?;
                let (inbox, receiver) = tokio::sync::mpsc::unbounded_channel();
                cleanup_receiver = Some(receiver);
                Some(CodexAppServer::start(inbox, Some(cwd)).await?)
            }
            (None, false) => None,
        };
        let mut seen_interruptions = HashSet::new();
        let interruptions = self.entries.iter().filter_map(|entry| {
            let server = server.as_ref()?.clone();
            let thread_id = entry.thread_id.as_ref()?.clone();
            let turn_id = entry.turn_id.as_ref()?.clone();
            seen_interruptions
                .insert((thread_id.clone(), turn_id.clone()))
                .then_some(async move {
                    server
                        .request(
                            "turn/interrupt",
                            json!({"threadId": thread_id, "turnId": turn_id}),
                        )
                        .await
                })
        });
        for result in futures_util::future::join_all(interruptions).await {
            if let Err(error) = result {
                if stale_codex_interrupt(&error) {
                    tracing::debug!(
                        error = %error.wire_message(),
                        "Codex cleanup found an already-stopped persisted turn"
                    );
                    continue;
                }
                return Err(error);
            }
        }
        let mut deleted_threads = HashSet::new();
        for entry in self.entries.iter().filter(|entry| entry.delete_thread) {
            let Some(thread_id) = entry
                .thread_id
                .as_ref()
                .filter(|thread_id| deleted_threads.insert((*thread_id).clone()))
            else {
                continue;
            };
            let Some(server) = server.as_ref() else {
                continue;
            };
            if let Err(error) = server
                .request("thread/delete", json!({"threadId": thread_id}))
                .await
            {
                tracing::warn!(
                    tab_id = %entry.tab_id,
                    error = %error.wire_message(),
                    "could not delete Codex thread after stopping active work"
                );
            }
        }
        drop(cleanup_receiver);
        Ok(self.entries)
    }
}

pub(in crate::terminal_host::server) async fn apply_cleanup_activity(
    runtime_store: &RuntimeStore,
    entries: &[CodexCleanupEntry],
) -> HostResult<Vec<String>> {
    let mut cleaned_tab_ids = Vec::new();
    for entry in entries {
        if let Some(tab_id) = clear_cleanup_activity(runtime_store, entry).await? {
            cleaned_tab_ids.push(tab_id);
        }
    }
    Ok(cleaned_tab_ids)
}

pub(in crate::terminal_host::server) async fn clear_cleanup_activity(
    runtime_store: &RuntimeStore,
    entry: &CodexCleanupEntry,
) -> HostResult<Option<String>> {
    let Some(mut tab) = runtime_store
        .find_workspace_tab(&entry.tab_id)
        .await
        .map_err(|error| HostError::state(error.to_string()))?
    else {
        return Ok(None);
    };
    if let Some(expected_thread_id) = entry.thread_id.as_deref() {
        if tab_thread_id(&tab).as_deref() != Some(expected_thread_id) {
            return Ok(None);
        }
    } else if tab_thread_id(&tab).is_some() {
        return Ok(None);
    }
    let mut next_snapshot = snapshot(&tab);
    let mut changed = false;
    if let Some(expected_turn_id) = entry.turn_id.as_deref() {
        if active_turn_id(&next_snapshot).is_some_and(|turn_id| turn_id != expected_turn_id) {
            return Ok(None);
        }
        clear_stale_thread_activity(&mut next_snapshot);
        persist_snapshot(&mut tab, next_snapshot);
        changed = true;
    }
    if let Some(replacement_cwd) = entry.replacement_cwd.as_deref() {
        if active_cwd(&tab).as_deref() != Some(replacement_cwd) {
            set_active_cwd(&mut tab, replacement_cwd);
            changed = true;
        }
    }
    if !changed {
        return Ok(None);
    }
    let saved = runtime_store
        .upsert_workspace_tab(tab)
        .await
        .map_err(|error| HostError::state(error.to_string()))?;
    Ok(Some(saved.id))
}

impl ServerActor {
    pub(crate) async fn plan_codex_workspace_cleanup(
        &self,
        workspace_id: &str,
    ) -> HostResult<Option<CodexCleanupPlan>> {
        let Some(target_workspace) = self
            .runtime_store
            .find_workspace(workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        else {
            return Ok(None);
        };
        self.plan_codex_workspaces_cleanup(&[target_workspace], false)
            .await
    }

    pub(crate) async fn plan_codex_project_cleanup(
        &self,
        project_id: &str,
    ) -> HostResult<Option<CodexCleanupPlan>> {
        let workspaces = self
            .runtime_store
            .list_workspaces(project_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.plan_codex_workspaces_cleanup(&workspaces, false).await
    }

    async fn plan_codex_workspaces_cleanup(
        &self,
        targets: &[Workspace],
        delete_owned_threads: bool,
    ) -> HostResult<Option<CodexCleanupPlan>> {
        let workspaces = self
            .runtime_store
            .list_all_workspaces()
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let mut entries = Vec::new();
        let mut fallback_cwd = None;
        for workspace in workspaces {
            let tabs = self
                .runtime_store
                .list_workspace_tabs(&workspace.id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
            for tab in tabs.into_iter().filter(is_codex_tab) {
                if !targets
                    .iter()
                    .any(|target| codex_tab_uses_workspace(&tab, target))
                {
                    continue;
                }
                let owner_is_removed = targets.iter().any(|target| target.id == workspace.id);
                let active_cwd_is_removed = active_cwd(&tab).is_some_and(|cwd| {
                    targets
                        .iter()
                        .any(|target| path_matches(&cwd, &target.path))
                });
                if !owner_is_removed && !active_cwd_is_removed {
                    continue;
                }
                let replacement_cwd =
                    (!owner_is_removed && active_cwd_is_removed).then(|| workspace.path.clone());
                let thread_id = tab_thread_id(&tab);
                let turn_id = active_turn_id(&snapshot(&tab));
                let delete_thread =
                    thread_id.is_some() && delete_owned_threads && thread_owned_by_alera(&tab);
                if turn_id.is_none() && !delete_thread && replacement_cwd.is_none() {
                    continue;
                }
                fallback_cwd.get_or_insert(workspace.path.clone());
                entries.push(CodexCleanupEntry {
                    tab_id: tab.id,
                    thread_id,
                    turn_id,
                    delete_thread,
                    replacement_cwd,
                });
            }
        }
        self.codex_cleanup_plan(entries, fallback_cwd)
    }

    pub(crate) async fn plan_codex_tab_cleanup(
        &self,
        tab_id: &str,
    ) -> HostResult<Option<CodexCleanupPlan>> {
        let Some(tab) = self
            .runtime_store
            .find_workspace_tab(tab_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        else {
            return Ok(None);
        };
        if !is_codex_tab(&tab) {
            return Ok(None);
        }
        let thread_id = tab_thread_id(&tab);
        let turn_id = active_turn_id(&snapshot(&tab));
        let delete_thread = thread_id.is_some() && thread_owned_by_alera(&tab);
        if turn_id.is_none() && !delete_thread {
            return Ok(None);
        }
        let fallback_cwd = self
            .runtime_store
            .find_workspace(&tab.workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .map(|workspace| workspace.path);
        self.codex_cleanup_plan(
            vec![CodexCleanupEntry {
                tab_id: tab.id,
                thread_id,
                turn_id,
                delete_thread,
                replacement_cwd: None,
            }],
            fallback_cwd,
        )
    }

    fn codex_cleanup_plan(
        &self,
        entries: Vec<CodexCleanupEntry>,
        fallback_cwd: Option<String>,
    ) -> HostResult<Option<CodexCleanupPlan>> {
        if entries.is_empty() {
            return Ok(None);
        }
        if self.codex.is_none() && fallback_cwd.is_none() {
            if entries.iter().any(|entry| entry.turn_id.is_some()) {
                return Err(HostError::state(
                    "Active Codex work could not be stopped because its workspace is unavailable.",
                ));
            }
            return Ok(None);
        }
        Ok(Some(CodexCleanupPlan {
            server: self.codex.clone(),
            fallback_cwd,
            entries,
        }))
    }
}

pub(super) fn stale_codex_interrupt(error: &HostError) -> bool {
    let message = error.wire_message().to_ascii_lowercase();
    [
        "thread not found",
        "turn not found",
        "turn not active",
        "no rollout found for thread id",
    ]
    .iter()
    .any(|expected| message.contains(expected))
}

pub(super) fn codex_tab_uses_workspace(tab: &WorkspaceTabRecord, workspace: &Workspace) -> bool {
    tab.workspace_id == workspace.id
        || active_cwd(tab).is_some_and(|cwd| path_matches(&cwd, &workspace.path))
}
