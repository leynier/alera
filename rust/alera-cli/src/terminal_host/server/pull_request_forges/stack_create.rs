//! `pullRequestStack.create`: pushes local workspace branches, opens the
//! pull requests they lack (each targeting the layer below), links them to
//! their workspaces, and stacks them, like the desktop's
//! `createReviewStackFromWorkspaces`.

use std::collections::BTreeSet;

use alera_core::runtime::{RuntimeStore, WorkspaceStatus};
use alera_core::source_control;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::super::identity::resolve_identity;
use super::{
    create_layer_review, git_host_error, require_local_workspace, spawn_blocking_workspace,
    stack_numbers, stack_top_branch, validate_chain, CreateInput, ForgeKind, NewLayer,
    StackContext,
};

pub(super) async fn create(
    store: &RuntimeStore,
    context: &StackContext,
    payload: &Value,
) -> HostResult<Value> {
    let current_branch = context
        .branch
        .clone()
        .or_else(|| {
            context
                .review
                .as_ref()
                .and_then(|review| review.head_branch.clone())
        })
        .ok_or_else(|| {
            HostError::state("The current workspace must have an active branch to create a stack.")
        })?;
    let requested = payload["layers"].as_array().cloned().unwrap_or_default();
    let existing = context.current_stack().await?;
    if existing.is_none() && requested.len() < 2 {
        return Err(HostError::state(
            "Choose at least two workspaces in bottom-to-top order.",
        ));
    }
    if existing.is_some() && requested.is_empty() {
        return Err(HostError::state("Choose at least one workspace to add."));
    }
    let base = match &existing {
        None => payload["baseBranch"]
            .as_str()
            .unwrap_or("")
            .trim()
            .to_string(),
        Some(stack) => stack_top_branch(stack).unwrap_or_default(),
    };
    if base.is_empty() {
        return Err(HostError::state(
            "Choose a valid base branch for the stack.",
        ));
    }
    let layers = resolve_layers(store, context, &requested).await?;
    let branches = layers
        .iter()
        .map(|layer| layer.branch.clone())
        .collect::<Vec<_>>();
    if existing.is_none() && !branches.contains(&current_branch) {
        return Err(HostError::state(
            "The current workspace must be included in the new stack.",
        ));
    }
    if let Some(stack) = &existing {
        let used = stack["entries"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|entry| entry["review"]["headRefName"].as_str())
            .collect::<BTreeSet<_>>();
        if let Some(duplicate) = branches
            .iter()
            .find(|branch| used.contains(branch.as_str()))
        {
            return Err(HostError::state(format!(
                "Branch `{duplicate}` is already in this stack."
            )));
        }
    }
    validate_chain(&context.workspace.path, &base, &branches).await?;
    for layer in &layers {
        let path = layer.workspace.path.clone();
        spawn_blocking_workspace("Stack push", move || {
            source_control::git_push(path).map_err(git_host_error)
        })
        .await?;
    }
    let mut numbers = Vec::new();
    let mut previous = base.clone();
    for mut layer in layers {
        layer.input.base = previous.clone();
        let (number, _) = create_layer_review(store, context.forge.as_ref(), &layer).await?;
        numbers.push(number);
        previous = layer.branch;
    }
    let stack_number = existing.as_ref().and_then(|stack| stack["number"].as_i64());
    let new_base = existing.is_none().then_some(base.as_str());
    let stack = context
        .stacks
        .link(&numbers, stack_number, new_base)
        .await?;
    Ok(json!({
        "provider": "github",
        "reviewNumbers": numbers,
        "stack": stack,
        "previousMembers": existing.as_ref().map(stack_numbers),
    }))
}

/// Each requested layer's workspace, live branch, and pull request details.
/// Every layer must be a distinct local workspace of the same repository.
async fn resolve_layers(
    store: &RuntimeStore,
    context: &StackContext,
    requested: &[Value],
) -> HostResult<Vec<NewLayer>> {
    let identity = context.forge.identity();
    let mut workspace_ids = BTreeSet::new();
    let mut branches = BTreeSet::new();
    let mut layers = Vec::new();
    for raw in requested {
        let workspace_id = raw["workspaceId"]
            .as_str()
            .map(str::trim)
            .filter(|id| !id.is_empty())
            .ok_or_else(|| HostError::state("Every stack layer needs a workspaceId."))?;
        if !workspace_ids.insert(workspace_id.to_string()) {
            return Err(HostError::state(
                "A workspace can appear only once in a stack.",
            ));
        }
        let workspace = store
            .find_workspace(workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .filter(|workspace| workspace.status == WorkspaceStatus::Active)
            .ok_or_else(|| HostError::state(format!("Workspace not found: {workspace_id}")))?;
        require_local_workspace(&workspace)?;
        let path = workspace.path.clone();
        let (branch, remote) = spawn_blocking_workspace("Stack layer", move || {
            Ok((
                alera_core::git::current_branch(&path).unwrap_or_default(),
                alera_core::git::repository_remote_url(&path).ok().flatten(),
            ))
        })
        .await?;
        let branch = branch.trim().to_string();
        if branch.is_empty() || branch == "HEAD" || !branches.insert(branch.clone()) {
            return Err(HostError::state(
                "Each stack layer must use a unique branch.",
            ));
        }
        let same_repository = remote
            .as_deref()
            .and_then(|url| resolve_identity(url, Some(ForgeKind::GitHub)))
            .is_some_and(|layer| {
                layer.host == identity.host
                    && layer.owner.eq_ignore_ascii_case(&identity.owner)
                    && layer.repo.eq_ignore_ascii_case(&identity.repo)
            });
        if !same_repository {
            return Err(HostError::state(format!(
                "Workspace `{branch}` does not belong to {}/{}/{}.",
                identity.host, identity.owner, identity.repo
            )));
        }
        let text = |key: &str| raw[key].as_str().map(str::trim).unwrap_or("").to_string();
        layers.push(NewLayer {
            input: CreateInput {
                base: String::new(),
                head: branch.clone(),
                title: text("title"),
                body: text("body"),
                draft: raw["draft"].as_bool().unwrap_or(false),
            },
            workspace,
            branch,
        });
    }
    Ok(layers)
}
