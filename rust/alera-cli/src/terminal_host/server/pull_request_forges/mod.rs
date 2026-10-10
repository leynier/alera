//! Pull requests on GitHub, GitLab, and Azure DevOps behind one
//! `ForgeProvider` (docs/mcp-parity-implementation-plan.md, section 6.4).
//!
//! The `mobile.pullRequest.*` verbs, Ship, Watch and Fix, stacks, and the
//! agent dispatch prompts all go through this module, so the phone, the CLI,
//! MCP, and the desktop get one behavior per forge. Each forge runs through its
//! own CLI (`gh`, `glab`, `az`) on the host that owns the checkout, so Alera
//! never holds a forge token. Everything here is additive to the strict
//! terminal-host and mobile protocols and is advertised by capability.

mod actions;
mod agent_dispatch;
mod azure;
mod azure_requests;
mod github;
mod gitlab;
mod identity;
mod input_file;
mod links;
mod local_command;
mod mappers;
mod model;
mod provider;
mod runner;
mod snapshot;
mod stack_actions;
mod stack_requests;
mod summaries;

#[cfg(test)]
mod fixture_tests;
#[cfg(test)]
mod provider_security_tests;
#[cfg(test)]
mod provider_tests;

use std::sync::Arc;

use alera_core::git as core_git;
use alera_core::runtime::{RuntimeStore, Workspace};

use crate::terminal_host::host_error::{HostError, HostResult};

pub(crate) use actions::run_forge_action;
#[cfg(test)]
pub(crate) use actions::{parse_forge_action, ForgeAction};
pub(crate) use identity::{resolve_identity, ForgeIdentity, ForgeKind};
pub(crate) use links::create_and_link;
#[cfg(test)]
pub(crate) use model::MergeMethod as ForgeMergeMethod;
pub(crate) use model::{preferred_merge_method, MergeMethod};
#[cfg(test)]
pub(crate) use provider::CommentSource as ForgeCommentSource;
pub(crate) use provider::{CreateInput, ForgeProvider};
pub(crate) use runner::{ForgeRunner, WorkspaceRunner};
pub(crate) use snapshot::{load_snapshot, snapshot_forge};
pub(crate) use stack_requests::{handle_stack_request, is_stack_verb};
pub(crate) use summaries::forge_project_summaries;

/// A provider for [identity]. Without [runner] the CLI runs in [repo_path] on
/// this machine.
pub(crate) fn build_forge(
    identity: ForgeIdentity,
    remote_url: &str,
    repo_path: &str,
    runner: Option<Arc<dyn ForgeRunner>>,
) -> Box<dyn ForgeProvider> {
    match identity.kind {
        ForgeKind::GitHub => {
            let runner = runner.unwrap_or_else(|| {
                Arc::new(github::GhRunner {
                    cwd: repo_path.to_string(),
                })
            });
            Box::new(github::GitHubForge {
                github: identity.github(remote_url),
                identity,
                repo_path: repo_path.to_string(),
                runner,
            })
        }
        ForgeKind::GitLab => Box::new(gitlab::GitLabForge {
            identity,
            runner: runner.unwrap_or_else(|| local_runner(repo_path)),
        }),
        ForgeKind::AzureDevOps => Box::new(azure::AzureDevOpsForge {
            identity,
            runner: runner.unwrap_or_else(|| local_runner(repo_path)),
        }),
    }
}

fn local_runner(repo_path: &str) -> Arc<dyn ForgeRunner> {
    Arc::new(runner::LocalRunner {
        cwd: repo_path.to_string(),
    })
}

/// What a checkout says about its forge: the branch, the remote, and the
/// provider (forced by the project's setting when it has one).
#[derive(Debug, Clone, Default)]
pub(crate) struct WorkspaceRemote {
    pub(crate) branch: Option<String>,
    pub(crate) remote_url: Option<String>,
    pub(crate) identity: Option<ForgeIdentity>,
}

pub(crate) async fn read_workspace_remote(
    store: &RuntimeStore,
    workspace: &Workspace,
) -> HostResult<WorkspaceRemote> {
    let path = workspace.path.clone();
    let (branch, remote_url) = tokio::task::spawn_blocking(move || {
        (
            core_git::current_branch(&path).ok(),
            core_git::repository_remote_url(&path).ok().flatten(),
        )
    })
    .await
    .map_err(|error| HostError::state(format!("Could not read the git remote: {error}")))?;
    let forced = project_forge_override(store, &workspace.project_id).await;
    let identity = remote_url
        .as_deref()
        .and_then(|url| identity::resolve_identity(url, forced));
    Ok(WorkspaceRemote {
        branch,
        remote_url,
        identity,
    })
}

/// The provider a project forces in its settings (`gitHostingProvider`).
pub(crate) async fn project_forge_override(
    store: &RuntimeStore,
    project_id: &str,
) -> Option<ForgeKind> {
    let config = store.find_project_config(project_id).await.ok()??;
    ForgeKind::from_wire(config.git_hosting_provider.as_deref()?)
}

/// The forge of a workspace whose checkout is on this machine.
pub(crate) async fn workspace_forge(
    store: &RuntimeStore,
    workspace: &Workspace,
) -> HostResult<(Box<dyn ForgeProvider>, WorkspaceRemote)> {
    let remote = read_workspace_remote(store, workspace).await?;
    let (Some(identity), Some(url)) = (remote.identity.clone(), remote.remote_url.as_deref())
    else {
        return Err(HostError::state(
            "No GitHub, GitLab, or Azure DevOps remote was detected for this workspace.",
        ));
    };
    Ok((build_forge(identity, url, &workspace.path, None), remote))
}

/// Refuses work the CLI would do on the wrong machine.
pub(crate) fn require_local_workspace(workspace: &Workspace) -> HostResult<()> {
    let host_id = workspace.host_id.trim();
    if !host_id.is_empty() && host_id != alera_core::runtime::LOCAL_HOST_ID {
        return Err(HostError::state(
            "Pull request actions are only available for workspaces on this runtime.",
        ));
    }
    Ok(())
}
