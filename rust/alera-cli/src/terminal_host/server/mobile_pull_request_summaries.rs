//! Compact per-workspace pull-request summaries for the mobile workspace
//! list, `mobile.pullRequest.summaries`.
//!
//! One GraphQL batch per repository, the same query the desktop forge layer
//! runs (`github_review_batch.dart`): branch lookups are open-only, linked
//! numbers are fetched by number, and the check rollup rides along so the
//! whole list costs one `gh` invocation per project. Check counting mirrors
//! `WorkspacePullRequestSummary.fromChecks` so a phone row and a desktop row
//! describe the same review identically.
//!
//! The response carries `eligibleWorkspaceIds` (every workspace considered)
//! and `evaluatedWorkspaceIds` (the groups whose batch completed) so the
//! phone merges like the desktop monitor: a failed `gh` batch leaves the
//! previous icons in place instead of reading as "these workspaces have no
//! PR", while an evaluated workspace with no review clears its stale icon. A
//! repository without a GitHub remote is a quiet empty group, never a warned
//! failure, because mobile pull requests are GitHub-only by design.

use std::collections::{BTreeMap, BTreeSet};

use alera_core::git as core_git;
use alera_core::runtime::{ProjectKind, RuntimeStore, Workspace, WorkspaceStatus};
use serde_json::{json, Value};
use tracing::warn;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::mobile_pull_request_identity::{parse_github_identity, GitHubIdentity};
use super::mobile_pull_request_requests::run_gh;

pub(super) async fn load_mobile_pull_request_summaries(
    runtime_store: &RuntimeStore,
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

    let mut by_project = BTreeMap::<&str, Vec<&Workspace>>::new();
    for workspace in &workspaces {
        if workspace.status != WorkspaceStatus::Active {
            continue;
        }
        if !git_project_ids.contains(&workspace.project_id) {
            continue;
        }
        let branch = workspace.branch.as_deref().unwrap_or("").trim();
        if branch.is_empty() || branch == "HEAD" {
            continue;
        }
        by_project
            .entry(workspace.project_id.as_str())
            .or_default()
            .push(workspace);
    }

    let mut summaries = Vec::<Value>::new();
    let mut eligible = BTreeSet::<String>::new();
    let mut evaluated = BTreeSet::<String>::new();
    for (project_id, group) in by_project {
        for workspace in &group {
            eligible.insert(workspace.id.clone());
        }
        let Some(repo_path) = projects
            .iter()
            .find(|project| project.id == project_id)
            .map(|project| project.repo_path.clone())
        else {
            continue;
        };
        match pull_request_summaries_for_project(runtime_store, &repo_path, &group).await {
            Ok(mut project_summaries) => {
                summaries.append(&mut project_summaries);
                for workspace in &group {
                    evaluated.insert(workspace.id.clone());
                }
            }
            Err(error) => {
                // A failed batch must not read as "these workspaces have no
                // PR": the group stays out of `evaluatedWorkspaceIds` so the
                // phone keeps its last-known icons and retries on the next
                // refresh, like the desktop monitor preserving `previous`.
                warn!(
                    "could not load mobile pull request summaries for {}: {error}",
                    project_id
                );
            }
        }
    }
    Ok(summaries_envelope(summaries, evaluated, eligible))
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

async fn pull_request_summaries_for_project(
    runtime_store: &RuntimeStore,
    repo_path: &str,
    group: &[&Workspace],
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
        // Mobile pull requests are GitHub-only, so a non-GitHub remote is a
        // quiet empty group: these rows genuinely have nothing to show, and
        // warning here would spam every refresh.
        return Ok(Vec::new());
    };

    let mut linked_numbers = BTreeMap::<&str, Option<i64>>::new();
    let mut dismissed_numbers = BTreeMap::<&str, Option<i64>>::new();
    let mut branches = Vec::<&str>::new();
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
        if let Some(number) = number {
            review_numbers.push(number);
        } else {
            branches.push(workspace.branch.as_deref().unwrap_or(""));
        }
        let dismissed = linked
            .filter(|review| review.dismissed)
            .and_then(|review| review.number);
        linked_numbers.insert(workspace.id.as_str(), number);
        dismissed_numbers.insert(workspace.id.as_str(), dismissed);
    }

    let batch = graphql_review_batch(repo_path, &identity, &branches, &review_numbers).await?;
    let mut summaries = Vec::<Value>::new();
    for workspace in group {
        let snapshot = summary_snapshot(
            linked_numbers[workspace.id.as_str()],
            dismissed_numbers[workspace.id.as_str()],
            workspace.branch.as_deref().unwrap_or(""),
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
    let state = snapshot
        .get("state")
        .and_then(Value::as_str)
        .unwrap_or("OPEN");
    let state = state.to_ascii_uppercase();
    let is_draft = snapshot
        .get("isDraft")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let display_state = match state.as_str() {
        "MERGED" => "merged",
        "CLOSED" => "closed",
        _ if is_draft => "draft",
        _ => "open",
    };
    let counts = count_check_contexts(&status_rollup_contexts(snapshot));
    json!({
        "workspaceId": workspace_id,
        "number": snapshot.get("number").and_then(Value::as_i64).unwrap_or(0),
        "title": snapshot.get("title").and_then(Value::as_str).unwrap_or(""),
        "url": snapshot.get("url").and_then(Value::as_str).unwrap_or(""),
        "state": display_state,
        "mergeable": snapshot.get("mergeable").and_then(Value::as_str),
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

fn status_rollup_contexts(snapshot: &Value) -> Vec<Value> {
    snapshot
        .get("commits")
        .and_then(|commits| commits.get("nodes"))
        .and_then(Value::as_array)
        .and_then(|nodes| nodes.first())
        .and_then(|node| node.get("commit"))
        .and_then(|commit| commit.get("statusCheckRollup"))
        .and_then(|rollup| rollup.get("contexts"))
        .and_then(|contexts| contexts.get("nodes"))
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
}

/// Rolled-up status across the checks of one review, mirroring
/// `deriveReviewChecksRollup` plus the counts the desktop sidebar keeps:
/// failure dominates, non-terminal runs count as pending, and at most three
/// failing names ride along for the row tooltip.
struct CheckCounts {
    rollup: &'static str,
    pending: i64,
    failed: i64,
    failing_names: Vec<String>,
}

fn count_check_contexts(contexts: &[Value]) -> CheckCounts {
    let mut pending = 0_i64;
    let mut failed = 0_i64;
    let mut failing_names = Vec::<String>::new();
    let mut any_pending = false;
    let mut any = false;
    for context in contexts {
        let Some((name, failed_check, pending_check)) = classify_check(context) else {
            continue;
        };
        any = true;
        if failed_check {
            failed += 1;
            if failing_names.len() < 3 {
                failing_names.push(name);
            }
            continue;
        }
        if pending_check {
            any_pending = true;
            pending += 1;
        }
    }
    let rollup = if !any {
        "none"
    } else if failed > 0 {
        "failure"
    } else if any_pending {
        "pending"
    } else {
        "success"
    };
    CheckCounts {
        rollup,
        pending,
        failed,
        failing_names,
    }
}

/// Maps one GraphQL `StatusCheckRollupContext` union entry to
/// `(name, failed, counts-as-pending)`, the neutral projection of
/// `mapGitHubStatusRollupCheck`. Modern Actions runs arrive as `CheckRun` and
/// legacy commit statuses as `StatusContext`.
fn classify_check(context: &Value) -> Option<(String, bool, bool)> {
    let name = || {
        context
            .get("name")
            .and_then(Value::as_str)
            .or_else(|| context.get("context").and_then(Value::as_str))
            .unwrap_or("check")
            .to_string()
    };
    if context.get("__typename").and_then(Value::as_str) == Some("StatusContext") {
        let state = context
            .get("state")
            .and_then(Value::as_str)
            .unwrap_or("PENDING")
            .to_ascii_uppercase();
        let pending = state == "EXPECTED" || state == "PENDING";
        let failed = state == "ERROR" || state == "FAILURE";
        return Some((name(), failed, pending));
    }
    let status = context
        .get("status")
        .and_then(Value::as_str)
        .unwrap_or("QUEUED")
        .to_ascii_uppercase();
    let completed = status == "COMPLETED";
    let conclusion = context
        .get("conclusion")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_ascii_uppercase();
    let failed = matches!(
        conclusion.as_str(),
        "FAILURE" | "STARTUP_FAILURE" | "CANCELLED" | "STALE" | "TIMED_OUT" | "ACTION_REQUIRED"
    );
    let pending = !completed || conclusion == "PENDING";
    Some((name(), failed, pending))
}

#[cfg(test)]
#[path = "mobile_pull_request_summaries_tests.rs"]
mod tests;
