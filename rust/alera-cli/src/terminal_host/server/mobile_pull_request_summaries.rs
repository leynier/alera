//! Compact per-workspace pull-request summaries for the mobile workspace list.
//!
//! One GraphQL batch per repository (`github_review_batch.dart` shape): open
//! branch lookups, linked numbers, and the check rollup. Project batches run
//! concurrently so a slow `gh` in one repo cannot starve the rest of the list
//! past the phone's two-minute timeout. A failed batch stays out of
//! `evaluatedWorkspaceIds` so the phone keeps last-known icons. Non-GitHub
//! remotes are a quiet empty group. A project whose folder lives on another
//! host is answered by that host (`mobile_pull_request_summaries_remote`).

use std::collections::{BTreeMap, BTreeSet};

use alera_core::git as core_git;
use alera_core::runtime::{Project, ProjectKind, RuntimeStore, Workspace, WorkspaceStatus};
use futures_util::future::join_all;
use serde_json::{json, Value};
use tracing::warn;

use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::host_link_registry::HostLinkRegistry;

use super::mobile_pull_request_check_counts::{
    count_check_contexts, status_rollup_contexts, CheckCounts,
};
use super::mobile_pull_request_identity::{parse_github_identity, GitHubIdentity};
use super::mobile_pull_request_requests::run_gh;

/// What one project contributed to the batch: its summaries and the
/// workspaces it could answer for.
#[derive(Debug, Default)]
pub(super) struct ProjectSummaries {
    pub(super) summaries: Vec<Value>,
    pub(super) evaluated: BTreeSet<String>,
}

pub(super) async fn load_mobile_pull_request_summaries(
    runtime_store: &RuntimeStore,
    links: &HostLinkRegistry,
) -> HostResult<Value> {
    let projects = runtime_store
        .list_projects()
        .await
        .map_err(|error| HostError::state(error.to_string()))?;
    let workspaces = runtime_store
        .list_all_workspaces()
        .await
        .map_err(|error| HostError::state(error.to_string()))?;
    let git_project_ids = projects
        .iter()
        .filter(|project| project.kind == ProjectKind::GitRepository)
        .map(|project| project.id.clone())
        .collect::<Vec<_>>();

    let mut by_project = BTreeMap::<String, Vec<Workspace>>::new();
    for workspace in workspaces {
        if workspace.status != WorkspaceStatus::Active {
            continue;
        }
        if !git_project_ids.contains(&workspace.project_id) {
            continue;
        }
        by_project
            .entry(workspace.project_id.clone())
            .or_default()
            .push(workspace);
    }

    let jobs = by_project.into_iter().filter_map(|(project_id, group)| {
        let project = projects.iter().find(|project| project.id == project_id)?;
        Some((project.clone(), group))
    });
    let results = join_all(jobs.map(|(project, group)| async move {
        let result = project_summaries(runtime_store, links, &project, &group).await;
        (group, result)
    }))
    .await;

    let mut summaries = Vec::<Value>::new();
    let mut eligible = BTreeSet::<String>::new();
    let mut evaluated = BTreeSet::<String>::new();
    for (group, result) in results {
        eligible.extend(group.iter().map(|workspace| workspace.id.clone()));
        summaries.extend(result.summaries);
        evaluated.extend(result.evaluated);
    }
    Ok(summaries_envelope(summaries, evaluated, eligible))
}

/// A project with a folder on this device gets the local batch; one whose
/// folder is on another host is asked there, because `repo_path` names a
/// directory on that machine and `gh` needs that host's credentials.
async fn project_summaries(
    runtime_store: &RuntimeStore,
    links: &HostLinkRegistry,
    project: &Project,
    group: &[Workspace],
) -> ProjectSummaries {
    if !crate::project_hosts::project_folder_is_local(runtime_store, project).await {
        return super::mobile_pull_request_summaries_remote::remote_project_summaries(
            runtime_store,
            links,
            &project.id,
            group,
        )
        .await;
    }
    match pull_request_summaries_for_project(runtime_store, &project.repo_path, group).await {
        Ok(summaries) => ProjectSummaries {
            summaries,
            evaluated: group.iter().map(|workspace| workspace.id.clone()).collect(),
        },
        Err(error) => {
            warn!(
                "could not load mobile pull request summaries for {}: {error}",
                project.id
            );
            ProjectSummaries::default()
        }
    }
}

/// The merge contract the phone implements: `summaries` replaces every
/// evaluated workspace (an evaluated workspace with no entry has no review),
/// unevaluated-but-eligible workspaces keep their previous icons, and
/// workspaces that left the eligible set are dropped.
fn summaries_envelope(
    summaries: Vec<Value>,
    evaluated: BTreeSet<String>,
    eligible: BTreeSet<String>,
) -> Value {
    json!({
        "summaries": summaries,
        "evaluatedWorkspaceIds": evaluated.into_iter().collect::<Vec<_>>(),
        "eligibleWorkspaceIds": eligible.into_iter().collect::<Vec<_>>(),
    })
}

async fn workspace_lookup_branch(workspace: &Workspace) -> Option<String> {
    if let Some(branch) = resolved_workspace_branch(workspace.branch.as_deref(), None) {
        return Some(branch);
    }
    let path = workspace.path.clone();
    let live = tokio::task::spawn_blocking(move || core_git::current_branch(&path).ok())
        .await
        .ok()
        .flatten();
    resolved_workspace_branch(None, live.as_deref())
}

fn resolved_workspace_branch(stored: Option<&str>, live: Option<&str>) -> Option<String> {
    for candidate in [stored, live] {
        let branch = candidate.unwrap_or("").trim();
        if !branch.is_empty() && branch != "HEAD" {
            return Some(branch.to_string());
        }
    }
    None
}

async fn pull_request_summaries_for_project(
    runtime_store: &RuntimeStore,
    repo_path: &str,
    group: &[Workspace],
) -> HostResult<Vec<Value>> {
    let remote_url = {
        let repo_path = repo_path.to_string();
        tokio::task::spawn_blocking(move || core_git::repository_remote_url(&repo_path))
            .await
            .map_err(|error| HostError::state(format!("Could not read the git remote: {error}")))?
            .ok()
            .flatten()
    };
    let identity = remote_url.as_deref().and_then(parse_github_identity);
    let Some(identity) = identity else {
        return Ok(Vec::new());
    };

    let mut linked_numbers = BTreeMap::<&str, Option<i64>>::new();
    let mut dismissed_numbers = BTreeMap::<&str, Option<i64>>::new();
    let mut head_branches = BTreeMap::<&str, String>::new();
    let mut branches = Vec::<String>::new();
    let mut review_numbers = Vec::<i64>::new();
    for workspace in group {
        let linked = runtime_store
            .find_linked_review(&workspace.id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let number = linked
            .as_ref()
            .filter(|review| !review.dismissed)
            .and_then(|review| review.number);
        let dismissed = linked
            .filter(|review| review.dismissed)
            .and_then(|review| review.number);
        let branch = workspace_lookup_branch(workspace).await;
        if let Some(number) = number {
            review_numbers.push(number);
        } else if let Some(branch) = branch.as_ref() {
            branches.push(branch.clone());
        } else {
            continue;
        }
        linked_numbers.insert(workspace.id.as_str(), number);
        dismissed_numbers.insert(workspace.id.as_str(), dismissed);
        head_branches.insert(workspace.id.as_str(), branch.unwrap_or_default());
    }

    let branch_refs = branches.iter().map(String::as_str).collect::<Vec<_>>();
    let batch = graphql_review_batch(repo_path, &identity, &branch_refs, &review_numbers).await?;
    let mut summaries = Vec::<Value>::new();
    for workspace in group {
        let Some(head_branch) = head_branches.get(workspace.id.as_str()) else {
            continue;
        };
        let snapshot = summary_snapshot(
            linked_numbers[workspace.id.as_str()],
            dismissed_numbers[workspace.id.as_str()],
            head_branch,
            &batch,
        );
        let Some(snapshot) = snapshot else {
            continue;
        };
        summaries.push(summary_json(workspace.id.as_str(), snapshot));
    }
    Ok(summaries)
}

fn summary_snapshot<'a>(
    linked_number: Option<i64>,
    dismissed_number: Option<i64>,
    branch: &str,
    batch: &'a BTreeMap<String, Value>,
) -> Option<&'a Value> {
    if let Some(number) = linked_number {
        return batch.get(&format!("review:{number}"));
    }
    let detected = batch.get(&format!("branch:{branch}"))?;
    let open = detected
        .get("state")
        .and_then(Value::as_str)
        .is_some_and(|state| state.eq_ignore_ascii_case("OPEN"));
    if !open {
        return None;
    }
    // An unlinked review stays hidden until the user links it again.
    if let Some(dismissed) = dismissed_number {
        let detected_number = detected.get("number").and_then(Value::as_i64);
        if detected_number == Some(dismissed) {
            return None;
        }
    }
    Some(detected)
}

fn summary_json(workspace_id: &str, snapshot: &Value) -> Value {
    let counts = count_check_contexts(&status_rollup_contexts(snapshot));
    review_summary_json(workspace_id, snapshot, &counts)
}

/// The summary row the phone renders, from a review object carrying the
/// GraphQL field names (`number`, `title`, `state`, `url`, `isDraft`,
/// `mergeable`) and the check counts computed by the caller.
pub(super) fn review_summary_json(
    workspace_id: &str,
    review: &Value,
    counts: &CheckCounts,
) -> Value {
    let state = review
        .get("state")
        .and_then(Value::as_str)
        .unwrap_or("OPEN");
    let state = state.to_ascii_uppercase();
    let is_draft = review
        .get("isDraft")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let display_state = match state.as_str() {
        "MERGED" => "merged",
        "CLOSED" => "closed",
        _ if is_draft => "draft",
        _ => "open",
    };
    json!({
        "workspaceId": workspace_id,
        "number": review.get("number").and_then(Value::as_i64).unwrap_or(0),
        "title": review.get("title").and_then(Value::as_str).unwrap_or(""),
        "url": review.get("url").and_then(Value::as_str).unwrap_or(""),
        "state": display_state,
        "mergeable": review.get("mergeable").and_then(Value::as_str),
        "checksRollup": counts.rollup,
        "pendingCheckCount": counts.pending,
        "failedCheckCount": counts.failed,
        "failingCheckNames": counts.failing_names,
    })
}

/// Runs the desktop's batch GraphQL query: one `pullRequests(first:1, ...)`
/// selection per unlinked branch (open-only, newest first) and one
/// `pullRequest(number:...)` selection per linked number, each with the check
/// rollup of its head commit.
async fn graphql_review_batch(
    repo_path: &str,
    identity: &GitHubIdentity,
    branches: &[&str],
    review_numbers: &[i64],
) -> HostResult<BTreeMap<String, Value>> {
    if branches.is_empty() && review_numbers.is_empty() {
        return Ok(BTreeMap::new());
    }
    // The query rides inside argv as `query=...`; the separate binding only
    // exists so tests can assert on the selection shape.
    let (_query, args) = review_batch_request(identity, branches, review_numbers);
    let arg_refs = args.iter().map(String::as_str).collect::<Vec<_>>();

    let (code, stdout, stderr) = run_gh(repo_path, &arg_refs).await?;
    if code != 0 {
        return Err(HostError::state(if stderr.is_empty() {
            stdout
        } else {
            stderr
        }));
    }
    let parsed: Value = serde_json::from_str(&stdout)
        .map_err(|error| HostError::state(format!("Could not parse gh output: {error}")))?;
    Ok(parse_review_batch_response(
        &parsed,
        branches,
        review_numbers,
    ))
}

/// Builds the `gh api graphql` query and argv for one repository batch. Pure
/// so the selection shape stays covered without spawning `gh`.
fn review_batch_request(
    identity: &GitHubIdentity,
    branches: &[&str],
    review_numbers: &[i64],
) -> (String, Vec<String>) {
    let mut query = String::from("query($owner:String!,$name:String!");
    let mut selections = String::new();
    for (index, _branch) in branches.iter().enumerate() {
        query.push_str(&format!(",$branch{index}:String!"));
        selections.push_str(&format!(
            "branch{index}:pullRequests(first:1,headRefName:$branch{index},"
        ));
        selections.push_str("states:[OPEN],orderBy:{field:CREATED_AT,direction:DESC})");
        selections.push_str("{nodes{...ReviewStatus}}");
    }
    for (index, _number) in review_numbers.iter().enumerate() {
        query.push_str(&format!(",$number{index}:Int!"));
        selections.push_str(&format!("review{index}:pullRequest(number:$number{index})"));
        selections.push_str("{...ReviewStatus}");
    }
    query.push(')');
    query.push_str("{repository(owner:$owner,name:$name){");
    query.push_str(&selections);
    query.push_str("}}");
    query.push_str("fragment ReviewStatus on PullRequest{");
    query.push_str("number title state url isDraft mergeable ");
    query.push_str("commits(last:1){nodes{commit{statusCheckRollup{contexts(first:100)");
    query.push_str("{nodes{__typename ");
    query.push_str("... on CheckRun{name status conclusion} ");
    query.push_str("... on StatusContext{context state}}}}}}}");

    let mut args = Vec::<String>::with_capacity(8 + branches.len() * 2 + review_numbers.len() * 2);
    args.extend([
        "api".to_string(),
        "graphql".to_string(),
        "--hostname".to_string(),
        identity.host.clone(),
        "-f".to_string(),
        format!("owner={}", identity.owner),
        "-f".to_string(),
        format!("name={}", identity.repo),
    ]);
    for (index, branch) in branches.iter().enumerate() {
        args.push("-f".to_string());
        args.push(format!("branch{index}={branch}"));
    }
    for (index, number) in review_numbers.iter().enumerate() {
        args.push("-F".to_string());
        args.push(format!("number{index}={number}"));
    }
    args.push("-f".to_string());
    args.push(format!("query={query}"));
    (query, args)
}

/// Indexes a batch GraphQL response by workspace lookup key: `branch:<name>`
/// for branch detections and `review:<number>` for linked numbers. A missing
/// branch connection or a null review stays absent, and a null entry must
/// never read as a review.
fn parse_review_batch_response(
    parsed: &Value,
    branches: &[&str],
    review_numbers: &[i64],
) -> BTreeMap<String, Value> {
    let repository = parsed
        .get("data")
        .and_then(|data| data.get("repository"))
        .cloned()
        .unwrap_or_else(|| json!({}));
    let mut batch = BTreeMap::<String, Value>::new();
    for (index, branch) in branches.iter().enumerate() {
        let node = repository
            .get(format!("branch{index}"))
            .and_then(|connection| connection.get("nodes"))
            .and_then(Value::as_array)
            .and_then(|nodes| nodes.first())
            .cloned();
        if let Some(node) = node {
            batch.insert(format!("branch:{branch}"), node);
        }
    }
    for (index, number) in review_numbers.iter().enumerate() {
        let node = repository.get(format!("review{index}")).cloned();
        if let Some(node) = node.filter(|node| !node.is_null()) {
            batch.insert(format!("review:{number}"), node);
        }
    }
    batch
}

#[cfg(test)]
#[path = "mobile_pull_request_summaries_tests.rs"]
mod tests;
