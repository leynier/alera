//! Ship for a paired phone: the desktop's one-tap path from local changes to a
//! pull request (`workspace_pull_request_ship_actions.dart`). It stages, writes
//! the commit message with AI Assist, moves the work off a shared base branch,
//! commits, pushes, and opens the pull request. It runs on the runtime rather
//! than as a sequence of phone requests, so a phone that sleeps halfway cannot
//! leave a commit without its pull request.

use alera_core::git as core_git;
use alera_core::runtime::{RuntimeStore, Workspace};
use alera_core::source_control::{self, GitChangeArea, GitErrorKind, GitRangeContext};
use regex::Regex;
use serde_json::json;
use tokio::sync::oneshot;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::ai_assist_commit_message::generate_commit_message;
use super::ai_assist_pull_request_details::{
    generate_pull_request_details, parse_pull_request_details,
};
use super::mobile_pull_request_actions::create_and_link;
use super::mobile_pull_request_identity::GitHubIdentity;
use super::mobile_source_control_snapshot::git_host_error;
use super::mobile_source_control_write_requests::WorkspaceWriteGuard;
use super::mobile_workspace_file_requests::spawn_blocking_workspace;

const MAX_BRANCH_CANDIDATES: usize = 100;
const MAX_BRANCH_SLUG_CHARS: usize = 48;

#[derive(Debug, Clone, Copy, PartialEq)]
pub(super) enum ShipScope {
    All,
    Staged,
}

#[derive(Debug, PartialEq)]
pub(super) struct ShipRequest {
    pub(super) base: String,
    pub(super) draft: bool,
    pub(super) scope: ShipScope,
}

/// What Ship has to do, decided from the working tree before anything moves.
#[derive(Debug, Clone, PartialEq)]
pub(super) struct ShipPlan {
    pub(super) source_branch: String,
    pub(super) needs_commit: bool,
    pub(super) move_off_base: bool,
    pub(super) tracking_ref: Option<String>,
    pub(super) source_oid: Option<String>,
    pub(super) unpushed_on_base: bool,
    pub(super) existing_message: Option<String>,
}

pub(super) async fn ship_pull_request(
    store: &RuntimeStore,
    workspace: &Workspace,
    identity: &GitHubIdentity,
    request: ShipRequest,
) -> HostResult<()> {
    let settings = store
        .effective_ai_assist_settings()
        .await
        .map_err(|error| HostError::state(error.to_string()))?;
    if !settings.enabled {
        return Err(HostError::state(
            "Enable AI Assist before shipping changes.",
        ));
    }
    // Shares the source control lock: a stage or commit from the Source
    // Control panel must not interleave with Ship's.
    let _guard = WorkspaceWriteGuard::acquire(&workspace.id)?;
    let root = workspace.path.clone();
    let plan = blocking({
        let root = root.clone();
        let base = request.base.clone();
        move || plan_ship(&root, &base, request.scope)
    })
    .await?;
    if plan.needs_commit && request.scope == ShipScope::All {
        blocking({
            let root = root.clone();
            move || source_control::git_stage(root, None).map_err(git_host_error)
        })
        .await?;
    }
    let message = if plan.needs_commit {
        let (_cancel, cancel_rx) = oneshot::channel();
        let generated = generate_commit_message(store, &workspace.id, cancel_rx).await?;
        let message = generated["message"]
            .as_str()
            .unwrap_or_default()
            .trim()
            .to_string();
        if message.is_empty() {
            return Err(HostError::state(
                "AI Assist returned an empty commit message.",
            ));
        }
        message
    } else {
        plan.existing_message
            .clone()
            .unwrap_or_else(|| "Update Project".to_string())
    };
    let head = if plan.move_off_base {
        blocking({
            let root = root.clone();
            let plan = plan.clone();
            let message = message.clone();
            move || move_off_base(&root, &plan, &message)
        })
        .await?
    } else {
        plan.source_branch.clone()
    };
    if plan.needs_commit {
        blocking({
            let root = root.clone();
            let message = message.clone();
            move || {
                source_control::git_commit(root, message)
                    .map(|_| ())
                    .map_err(git_host_error)
            }
        })
        .await?;
    }
    let finish = async {
        let (_cancel, cancel_rx) = oneshot::channel();
        // A commit already exists, so optional details must never strand it:
        // fall back to the commit message like the desktop.
        let details =
            match generate_pull_request_details(store, &workspace.id, &request.base, cancel_rx)
                .await
            {
                Ok((details, _)) => details,
                Err(_) => parse_pull_request_details(&message),
            };
        blocking({
            let root = root.clone();
            move || source_control::git_push(root).map_err(git_host_error)
        })
        .await?;
        create_and_link(
            store,
            workspace,
            identity,
            &request.base,
            &head,
            &details.title,
            details.body.as_deref().unwrap_or_default(),
            request.draft,
        )
        .await
    }
    .await;
    finish.map_err(|error| {
        if plan.needs_commit {
            after_commit(error)
        } else {
            error
        }
    })
}

async fn blocking<T: Send + 'static>(
    work: impl FnOnce() -> HostResult<T> + Send + 'static,
) -> HostResult<T> {
    spawn_blocking_workspace("Ship", work).await
}

pub(super) fn plan_ship(root: &str, base: &str, scope: ShipScope) -> HostResult<ShipPlan> {
    let base = base.trim();
    if base.is_empty() {
        return Err(HostError::state("Select a base branch before shipping."));
    }
    let status = source_control::git_status(root.to_string()).map_err(git_host_error)?;
    let source_branch = core_git::current_branch(root).map_err(git_host_error)?;
    if source_branch.is_empty() || source_branch == "HEAD" {
        return Err(HostError::state("Check out a branch before shipping."));
    }
    let has_staged = status
        .entries
        .iter()
        .any(|entry| entry.area == GitChangeArea::Staged);
    let has_leftovers = status
        .entries
        .iter()
        .any(|entry| entry.area != GitChangeArea::Staged);
    let needs_commit = match scope {
        ShipScope::All => !status.entries.is_empty(),
        ShipScope::Staged => has_staged,
    };
    if scope == ShipScope::Staged && has_leftovers {
        return Err(HostError::state(
            "Stage at least one change before shipping.",
        ));
    }
    let head_ref = format!("refs/heads/{source_branch}");
    let move_off_base = requires_ship_branch(&source_branch, base);
    let mut plan = ShipPlan {
        source_branch: source_branch.clone(),
        needs_commit,
        move_off_base,
        tracking_ref: None,
        source_oid: None,
        unpushed_on_base: false,
        existing_message: None,
    };
    if move_off_base {
        source_control::git_fetch(root.to_string()).map_err(git_host_error)?;
        let tracking_ref = format!("refs/remotes/origin/{source_branch}");
        let range = range_ahead(root, &tracking_ref, &head_ref).map_err(|error| {
            if error.kind == GitErrorKind::BranchNotFound {
                HostError::state(format!(
                    "Could not find {tracking_ref} after fetch. Fetch the remote tracking branch before shipping."
                ))
            } else {
                git_host_error(error)
            }
        })?;
        plan.unpushed_on_base = !range.commits.is_empty();
        plan.source_oid = Some(range.head_oid.clone());
        if plan.unpushed_on_base {
            plan.existing_message = commit_message_from_range(&range);
        }
        plan.tracking_ref = Some(tracking_ref);
    } else if !needs_commit {
        let range = range_ahead(root, base, &head_ref).map_err(git_host_error)?;
        if range.commits.is_empty() {
            return Err(HostError::state("No changes to ship."));
        }
        plan.existing_message = commit_message_from_range(&range);
    }
    if !needs_commit && move_off_base && !plan.unpushed_on_base {
        return Err(HostError::state("No changes to ship."));
    }
    Ok(plan)
}

fn range_ahead(
    root: &str,
    base_ref: &str,
    head_ref: &str,
) -> Result<GitRangeContext, source_control::GitError> {
    source_control::git_range_context(
        root.to_string(),
        base_ref.to_string(),
        None,
        Some(head_ref.to_string()),
    )
}

/// Moves the work to a new `ship/...` branch, and puts a base branch with
/// unpushed commits back on its remote tip so the shared branch stays clean.
fn move_off_base(root: &str, plan: &ShipPlan, message: &str) -> HostResult<String> {
    let branch = available_ship_branch_name(root, message)?;
    core_git::create_and_checkout_branch_from(
        root,
        &branch,
        Some(&plan.source_branch),
        plan.source_oid.as_deref(),
    )
    .map_err(git_host_error)?;
    if plan.unpushed_on_base {
        if let Some(tracking_ref) = &plan.tracking_ref {
            core_git::reset_branch_to_ref_from(
                root,
                &plan.source_branch,
                tracking_ref,
                plan.source_oid.as_deref(),
            )
            .map_err(git_host_error)?;
        }
    }
    Ok(branch)
}

pub(super) fn requires_ship_branch(head: &str, base: &str) -> bool {
    head == base || head == "main" || head == "master"
}

fn available_ship_branch_name(root: &str, message: &str) -> HostResult<String> {
    let base = ship_branch_base(message);
    for index in 1..=MAX_BRANCH_CANDIDATES {
        let candidate = if index == 1 {
            base.clone()
        } else {
            format!("{base}-{index}")
        };
        if !core_git::is_valid_branch_name(&candidate).map_err(git_host_error)? {
            continue;
        }
        if !core_git::branch_exists(root, &candidate).map_err(git_host_error)? {
            return Ok(candidate);
        }
    }
    Err(HostError::state(
        "Could not find an available branch name for the staged changes.",
    ))
}

/// `ship/<slug>` from the commit subject without its conventional prefix,
/// like the desktop's `_shipBranchBase`.
pub(super) fn ship_branch_base(message: &str) -> String {
    let prefix = Regex::new(r"^[a-zA-Z]+(?:\([^)]+\))?!?:\s*").expect("valid regex");
    let separators = Regex::new("[^a-z0-9]+").expect("valid regex");
    let subject = message.lines().next().unwrap_or_default().trim();
    let subject = prefix.replace(subject, "").to_lowercase();
    let slug = separators.replace_all(&subject, "-");
    let mut slug = slug.trim_matches('-').to_string();
    if slug.is_empty() {
        slug = "changes".to_string();
    }
    if slug.len() > MAX_BRANCH_SLUG_CHARS {
        slug = slug[..MAX_BRANCH_SLUG_CHARS]
            .trim_end_matches('-')
            .to_string();
    }
    format!("ship/{slug}")
}

fn commit_message_from_range(range: &GitRangeContext) -> Option<String> {
    range.commits.iter().find_map(|commit| {
        let message = commit.message.trim();
        let subject = commit.subject.trim();
        if !message.is_empty() {
            Some(message.to_string())
        } else if !subject.is_empty() {
            Some(subject.to_string())
        } else {
            None
        }
    })
}

/// Keeps the failure's code but says the commit already happened, so the user
/// does not ship the same changes twice.
fn after_commit(error: HostError) -> HostError {
    let code = error.wire_response(0)["errorCode"]
        .as_str()
        .unwrap_or("shipIncomplete")
        .to_string();
    HostError::conflict(
        code,
        format!(
            "The changes were committed, but Ship could not finish: {}",
            error.wire_message()
        ),
        json!({}),
    )
}

#[cfg(test)]
#[path = "mobile_pull_request_ship_tests.rs"]
mod tests;
