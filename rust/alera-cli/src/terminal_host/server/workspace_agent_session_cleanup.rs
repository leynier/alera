//! Deletes the native agent conversations of a workspace the user removed,
//! when the runtime setting asks for it.
//!
//! The workspace record and its tabs are gone once the removal commits, so
//! what the cleanup needs is captured just before it. The cleanup itself runs
//! on its own task after the removal succeeded: a slow or failing agent CLI
//! must never delay or fail the removal the user asked for.

use std::collections::HashSet;

use alera_core::runtime::{RuntimeStore, Workspace, WorkspaceKind, LOCAL_HOST_ID};

use crate::native_agent_sessions::{
    run_native_session_cleanup, NativeAgentSessionRef, NativeSessionCleanupPlan,
    NativeSessionCleanupScope,
};

use super::agent_native_session::native_session_resume;
use super::runtime_mutations::RuntimeMutationRequest;

pub(super) struct PendingAgentSessionCleanup {
    workspace_id: String,
    plan: NativeSessionCleanupPlan,
}

/// The cleanup a removal would trigger, or `None` when the setting is off,
/// the mutation is not a user's workspace removal, or the workspace lives on
/// another host (its conversations are on that machine).
pub(super) async fn capture_agent_session_cleanup(
    store: &RuntimeStore,
    mutation: &RuntimeMutationRequest,
) -> Option<PendingAgentSessionCleanup> {
    let workspace_id = match mutation {
        RuntimeMutationRequest::RemoveManagedWorkspace { request } => &request.id,
        RuntimeMutationRequest::RemoveSharedWorkspace {
            request,
            automation_cleanup: None,
            remote_automation_cleanup: None,
            ..
        } => &request.id,
        _ => return None,
    };
    if !store
        .delete_agent_sessions_on_workspace_removal()
        .await
        .unwrap_or(false)
    {
        return None;
    }
    let workspace = store.find_workspace(workspace_id).await.ok().flatten()?;
    if workspace.host_id != LOCAL_HOST_ID {
        return None;
    }
    match agent_session_cleanup_plan(store, &workspace).await {
        Ok(plan) => Some(PendingAgentSessionCleanup {
            workspace_id: workspace.id,
            plan,
        }),
        Err(error) => {
            tracing::warn!(%error, workspace_id = %workspace.id, "could not plan agent session cleanup");
            None
        }
    }
}

async fn agent_session_cleanup_plan(
    store: &RuntimeStore,
    workspace: &Workspace,
) -> anyhow::Result<NativeSessionCleanupPlan> {
    let mut seen = HashSet::new();
    let mut sessions = Vec::new();
    for record in store.list_agent_native_sessions(&workspace.id).await? {
        if seen.insert((record.agent_type.clone(), record.session_id.clone())) {
            sessions.push(NativeAgentSessionRef {
                agent_type: record.agent_type,
                session_id: record.session_id,
                ccs_profile: record.ccs_profile,
                cwd: record.cwd,
            });
        }
    }
    // The ledger is written on the same hook as the tab binding, but a tab's
    // current binding is what a resume would use, so it is never missed.
    for tab in store.list_workspace_tabs(&workspace.id).await? {
        let Some(resume) = native_session_resume(&tab) else {
            continue;
        };
        if seen.insert((resume.agent_type.to_string(), resume.session_id.to_string())) {
            sessions.push(NativeAgentSessionRef {
                agent_type: resume.agent_type.to_string(),
                session_id: resume.session_id.to_string(),
                ccs_profile: super::agent_native_session::native_ccs_profile(&tab)
                    .map(str::to_string),
                cwd: None,
            });
        }
    }
    let preserved = store
        .agent_native_sessions_outside(&workspace.id)
        .await?
        .into_iter()
        .map(|(agent_type, session_id)| NativeAgentSessionRef {
            agent_type,
            session_id,
            ccs_profile: None,
            cwd: None,
        })
        .collect::<Vec<_>>();
    let preserved_keys = preserved
        .iter()
        .map(|session| (session.agent_type.as_str(), session.session_id.as_str()))
        .collect::<HashSet<_>>();
    sessions.retain(|session| {
        !preserved_keys.contains(&(session.agent_type.as_str(), session.session_id.as_str()))
    });
    Ok(NativeSessionCleanupPlan {
        workspace_path: workspace.path.clone(),
        // Only a linked worktree's directory is deleted with the workspace.
        // The main checkout stays, and so does whatever else ran there.
        scope: if workspace.kind == WorkspaceKind::Linked {
            NativeSessionCleanupScope::WorkspacePath
        } else {
            NativeSessionCleanupScope::RegisteredSessions
        },
        sessions,
        preserved,
    })
}

/// Runs a captured cleanup after its removal committed, then forgets the
/// ledger rows of every workspace that no longer exists.
pub(super) fn spawn_agent_session_cleanup(
    store: RuntimeStore,
    pending: Option<PendingAgentSessionCleanup>,
) {
    tokio::spawn(async move {
        if let Some(PendingAgentSessionCleanup { workspace_id, plan }) = pending {
            let outcomes = run_native_session_cleanup(plan).await;
            let failed = outcomes
                .iter()
                .filter(|outcome| outcome.result.is_err())
                .count();
            for outcome in outcomes.iter().filter(|outcome| outcome.result.is_err()) {
                tracing::warn!(
                    workspace_id,
                    agent_type = outcome.agent_type,
                    target = outcome.target,
                    error = outcome
                        .result
                        .as_ref()
                        .err()
                        .map(String::as_str)
                        .unwrap_or_default(),
                    "agent session cleanup step failed"
                );
            }
            tracing::info!(
                workspace_id,
                steps = outcomes.len(),
                failed,
                "agent session cleanup finished"
            );
        }
        if let Err(error) = store.prune_orphan_agent_native_sessions().await {
            tracing::warn!(%error, "could not prune the agent session ledger");
        }
    });
}

#[cfg(test)]
#[path = "workspace_agent_session_cleanup_tests.rs"]
mod tests;
