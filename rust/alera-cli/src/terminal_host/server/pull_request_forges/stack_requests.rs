//! `pullRequestStack.get|create|link|merge`: the desktop's stack actions
//! (`workspace_pull_request_stack_actions.dart` and
//! `workspace_pull_request_stack_validation.dart`) on the runtime, with the
//! same validation and messages. GitHub only, like the desktop; other forges
//! answer `provider_unsupported`.

use std::sync::Arc;

use alera_core::runtime::{LinkedReview, RuntimeStore, Workspace};
use alera_core::source_control::{self, GitErrorKind};
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::super::mobile_pull_request_busy::BusyGuard;
use super::super::mobile_source_control_snapshot::git_host_error;
use super::super::mobile_workspace_file_requests::{
    spawn_blocking_workspace, workspace_for_mobile_file_request,
};
use super::super::requests::optional_string_key;
use super::github::GhRunner;
use super::links::{create_and_link, save_link};
use super::model::{provider_unsupported, MergeMethod, Review};
use super::provider::{CreateInput, ForgeProvider};
use super::stack_actions::GitHubStacks;
use super::{require_local_workspace, workspace_forge, ForgeKind};

pub(crate) fn is_stack_verb(request_type: &str) -> bool {
    matches!(
        request_type,
        "pullRequestStack.get"
            | "pullRequestStack.create"
            | "pullRequestStack.link"
            | "pullRequestStack.merge"
    )
}

struct StackContext {
    workspace: Workspace,
    forge: Box<dyn ForgeProvider>,
    stacks: GitHubStacks,
    branch: Option<String>,
    linked: Option<LinkedReview>,
    review: Option<Review>,
}

pub(crate) async fn handle_stack_request(
    store: &RuntimeStore,
    request_type: &str,
    payload: &Value,
) -> HostResult<Value> {
    if let Some(workspace_id) = payload.get("workspaceId").and_then(Value::as_str) {
        super::super::remote_pull_request_routing::adopt_hub_linked_review(
            store,
            workspace_id,
            payload,
        )
        .await?;
    }
    let workspace = workspace_for_mobile_file_request(store, payload).await?;
    let context = open(store, workspace, payload).await?;
    let mut result = match request_type {
        "pullRequestStack.get" => get(&context).await?,
        "pullRequestStack.link" => {
            let _busy = BusyGuard::acquire(&context.workspace.id)?;
            link(store, &context, payload).await?
        }
        "pullRequestStack.create" => {
            let _busy = BusyGuard::acquire(&context.workspace.id)?;
            create(store, &context, payload).await?
        }
        "pullRequestStack.merge" => {
            let _busy = BusyGuard::acquire(&context.workspace.id)?;
            merge(store, &context, payload).await?
        }
        other => {
            return Err(HostError::format(format!(
                "Unknown pull request stack request: {other}"
            )))
        }
    };
    // A hub adopts the link the satellite reports, as for the other verbs.
    let linked = store
        .find_linked_review(&context.workspace.id)
        .await
        .map_err(|error| HostError::state(error.to_string()))?;
    result["linkedReview"] = linked.map_or(Value::Null, |review| {
        json!({
            "number": review.number,
            "url": review.url,
            "provider": review.provider,
            "dismissed": review.dismissed,
        })
    });
    Ok(result)
}

async fn open(
    store: &RuntimeStore,
    workspace: Workspace,
    payload: &Value,
) -> HostResult<StackContext> {
    require_local_workspace(&workspace)?;
    let (forge, remote) = workspace_forge(store, &workspace).await?;
    if forge.kind() != ForgeKind::GitHub {
        return Err(provider_unsupported(
            "Pull request stacks are only available for GitHub repositories, as on desktop.",
        ));
    }
    let github = forge
        .identity()
        .github(remote.remote_url.as_deref().unwrap_or_default());
    let stacks = GitHubStacks {
        github,
        runner: Arc::new(GhRunner {
            cwd: workspace.path.clone(),
        }),
    };
    let linked = store
        .find_linked_review(&workspace.id)
        .await
        .map_err(|error| HostError::state(error.to_string()))?;
    let requested = payload.get("number").and_then(Value::as_i64);
    let linked_number = linked
        .as_ref()
        .filter(|review| !review.dismissed)
        .and_then(|review| review.number);
    let review = match (requested.or(linked_number), remote.branch.as_deref()) {
        (Some(number), _) => forge.review_by_number(number).await?,
        (None, Some(branch)) => forge.review_for_branch(branch).await?,
        (None, None) => None,
    };
    Ok(StackContext {
        workspace,
        forge,
        stacks,
        branch: remote
            .branch
            .filter(|branch| !branch.is_empty() && branch != "HEAD"),
        linked,
        review,
    })
}

impl StackContext {
    fn linked_manually(&self) -> bool {
        let current = self.review.as_ref().map(|review| review.number);
        self.linked
            .as_ref()
            .is_some_and(|review| !review.dismissed && review.number == current)
    }

    async fn current_stack(&self) -> HostResult<Option<Value>> {
        match &self.review {
            Some(review) => self.stacks.stack_for_review(review.number).await,
            None => Ok(None),
        }
    }

    /// Links the current review the way the desktop does after a stack
    /// action, unless the user already pinned one.
    async fn keep_link(&self, store: &RuntimeStore) -> HostResult<()> {
        let Some(review) = &self.review else {
            return Ok(());
        };
        if self.linked_manually() {
            return Ok(());
        }
        let url = Some(review.url.clone()).filter(|url| !url.is_empty());
        save_link(
            store,
            &self.workspace.id,
            ForgeKind::GitHub,
            review.number,
            url,
            false,
        )
        .await
    }
}

async fn get(context: &StackContext) -> HostResult<Value> {
    let stack = context.current_stack().await?;
    Ok(json!({
        "provider": "github",
        "reviewNumber": context.review.as_ref().map(|review| review.number),
        "stack": stack,
        "extensionInstalled": context.stacks.extension_installed().await,
    }))
}

fn normalize(numbers: impl IntoIterator<Item = i64>) -> Vec<i64> {
    let mut seen = std::collections::BTreeSet::new();
    numbers
        .into_iter()
        .filter(|number| *number > 0 && seen.insert(*number))
        .collect()
}

fn stack_numbers(stack: &Value) -> Vec<i64> {
    stack["entries"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|entry| entry["review"]["number"].as_i64())
        .collect()
}

fn stack_top_branch(stack: &Value) -> Option<String> {
    stack["entries"].as_array()?.last()?["review"]["headRefName"]
        .as_str()
        .map(ToOwned::to_owned)
}

async fn link(store: &RuntimeStore, context: &StackContext, payload: &Value) -> HostResult<Value> {
    let current = context
        .review
        .as_ref()
        .ok_or_else(|| HostError::state("Native pull request stacks are not available."))?;
    let numbers = normalize(
        payload["numbers"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(Value::as_i64),
    );
    let existing = context.current_stack().await?;
    match &existing {
        None if numbers.len() < 2 => {
            return Err(HostError::state(
                "Choose at least two pull requests in bottom-to-top order.",
            ));
        }
        None if !numbers.contains(&current.number) => {
            return Err(HostError::state(
                "The current pull request must be included in the new stack.",
            ));
        }
        Some(_) if numbers.is_empty() => {
            return Err(HostError::state("Choose at least one pull request to add."));
        }
        Some(stack) => {
            let members = stack_numbers(stack);
            if let Some(duplicate) = numbers.iter().find(|number| members.contains(number)) {
                return Err(HostError::state(format!(
                    "Pull request #{duplicate} is already in this stack."
                )));
            }
        }
        None => {}
    }
    let mut reviews = Vec::new();
    for number in &numbers {
        let review = context
            .forge
            .review_by_number(*number)
            .await?
            .ok_or_else(|| HostError::state(format!("No pull request #{number} was found.")))?;
        if !review.is_open() {
            return Err(HostError::state(format!(
                "Pull request #{number} is not open."
            )));
        }
        reviews.push(review);
    }
    let base = existing
        .as_ref()
        .and_then(stack_top_branch)
        .or_else(|| {
            reviews
                .first()
                .and_then(|review| review.base_branch.clone())
        })
        .ok_or_else(|| HostError::state("Could not determine the base branch for this stack."))?;
    let mut branches = Vec::new();
    for review in &reviews {
        branches.push(
            review
                .head_branch
                .clone()
                .filter(|b| !b.trim().is_empty())
                .ok_or_else(|| {
                    HostError::state(format!(
                        "Pull request #{} does not expose a head branch.",
                        review.number
                    ))
                })?,
        );
    }
    validate_chain(&context.workspace.path, &base, &branches).await?;
    let stack_number = existing.as_ref().and_then(|stack| stack["number"].as_i64());
    let first_base = reviews
        .first()
        .and_then(|review| review.base_branch.clone());
    let stack = context
        .stacks
        .link(
            &numbers,
            stack_number,
            if existing.is_none() {
                first_base.as_deref()
            } else {
                None
            },
        )
        .await?;
    context.keep_link(store).await?;
    Ok(json!({ "provider": "github", "stack": stack }))
}

/// Every branch descends from the one below it, starting at [base]. A
/// missing branch triggers one fetch, as on desktop.
async fn validate_chain(repo_path: &str, base: &str, branches: &[String]) -> HostResult<()> {
    let repo_path = repo_path.to_string();
    let base = base.trim().to_string();
    let branches = branches.to_vec();
    spawn_blocking_workspace("Stack validation", move || {
        let mut previous = base;
        if previous.is_empty() {
            return Err(HostError::state("Could not determine the base branch for this stack."));
        }
        let mut fetched = false;
        for branch in branches.iter().map(|branch| branch.trim()) {
            if branch.is_empty() {
                return Err(HostError::state("Every stack layer needs a branch."));
            }
            if branch == previous {
                return Err(HostError::state(format!(
                    "Branch `{branch}` is also used by the layer below it."
                )));
            }
            let check = || {
                source_control::is_ancestor(repo_path.clone(), previous.clone(), branch.to_string())
            };
            let descends = match check() {
                Err(error) if error.kind == GitErrorKind::BranchNotFound && !fetched => {
                    source_control::git_fetch(repo_path.clone()).map_err(git_host_error)?;
                    fetched = true;
                    check().map_err(git_host_error)?
                }
                other => other.map_err(git_host_error)?,
            };
            if !descends {
                return Err(HostError::state(format!(
                    "Branch `{branch}` must descend from `{previous}` before its pull request can join the stack."
                )));
            }
            previous = branch.to_string();
        }
        Ok(())
    })
    .await
}

#[path = "stack_create.rs"]
mod stack_create;
use stack_create::create;

async fn merge(store: &RuntimeStore, context: &StackContext, payload: &Value) -> HostResult<Value> {
    let (Some(review), Some(stack)) = (&context.review, context.current_stack().await?) else {
        return Err(HostError::state(
            "No pull request stack is available to merge.",
        ));
    };
    let allowed = context
        .forge
        .merge_methods(review.base_branch.as_deref())
        .await
        .map_err(HostError::state)?;
    let method = match optional_string_key(payload, "method") {
        Some(method) => method,
        None => allowed.first().cloned().unwrap_or_default(),
    };
    if !allowed.contains(&method) || method == "providerDefault" {
        return Err(HostError::state(
            "This stack cannot use the selected merge method.",
        ));
    }
    let entries = stack["entries"].as_array().cloned().unwrap_or_default();
    let position = entries
        .iter()
        .find(|entry| entry["review"]["number"].as_i64() == Some(review.number))
        .and_then(|entry| entry["position"].as_i64())
        .ok_or_else(|| HostError::state("The current pull request is not in this stack."))?;
    let blocked = entries.iter().find(|entry| {
        entry["position"].as_i64().unwrap_or(i64::MAX) <= position
            && (entry["review"]["isDraft"] == true || entry["review"]["state"] == "CLOSED")
    });
    if let Some(entry) = blocked {
        return Err(HostError::state(format!(
            "Pull request #{} must be open and ready before merging the stack.",
            entry["review"]["number"]
        )));
    }
    let method = MergeMethod::parse(&method)
        .ok_or_else(|| HostError::state("This stack cannot use the selected merge method."))?;
    context.stacks.merge(review.number, method).await?;
    context.keep_link(store).await?;
    Ok(json!({
        "provider": "github",
        "merged": true,
        "reviewNumber": review.number,
        "method": method.wire(),
        "mergedThrough": position,
    }))
}

/// Inputs shared with `stack_create`.
pub(super) struct NewLayer {
    pub(super) workspace: Workspace,
    pub(super) branch: String,
    pub(super) input: CreateInput,
}

pub(super) async fn create_layer_review(
    store: &RuntimeStore,
    context_forge: &dyn ForgeProvider,
    layer: &NewLayer,
) -> HostResult<(i64, Option<String>)> {
    if let Some(review) = context_forge.review_for_branch(&layer.branch).await? {
        if !review.is_open() {
            return Err(HostError::state(format!(
                "Pull request #{} for `{}` is not open.",
                review.number, layer.branch
            )));
        }
        let url = Some(review.url).filter(|url| !url.is_empty());
        save_link(
            store,
            &layer.workspace.id,
            ForgeKind::GitHub,
            review.number,
            url.clone(),
            false,
        )
        .await?;
        return Ok((review.number, url));
    }
    if layer.input.title.trim().is_empty() {
        return Err(HostError::state("Every new pull request needs a title."));
    }
    let created = create_and_link(store, &layer.workspace, context_forge, &layer.input)
        .await
        .map_err(|error| {
            HostError::state(format!(
                "Could not create the pull request for `{}`: {}",
                layer.branch,
                error.wire_message()
            ))
        })?;
    Ok((created.number, created.url))
}
