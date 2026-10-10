//! Per-workspace summary rows for GitLab and Azure DevOps projects. Their CLIs
//! have no batch query like GitHub's GraphQL, so each workspace is read on its
//! own (linked number, else the open review of its branch, then its checks),
//! a few at a time.

use alera_core::runtime::{RuntimeStore, Workspace};
use futures_util::future::join_all;
use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::super::mobile_pull_request_check_counts::count_classified_checks;
use super::super::mobile_pull_request_summaries::{review_summary_json, workspace_lookup_branch};
use super::build_forge;
use super::identity::ForgeIdentity;
use super::model::classify_check;
use super::provider::ForgeProvider;

const CONCURRENT_WORKSPACES: usize = 4;

pub(crate) async fn forge_project_summaries(
    store: &RuntimeStore,
    repo_path: &str,
    identity: ForgeIdentity,
    remote_url: &str,
    group: &[Workspace],
) -> HostResult<Vec<Value>> {
    let forge = build_forge(identity, remote_url, repo_path, None);
    let forge = forge.as_ref();
    let mut rows = Vec::with_capacity(group.len());
    for chunk in group.chunks(CONCURRENT_WORKSPACES) {
        rows.extend(
            join_all(
                chunk
                    .iter()
                    .map(|workspace| workspace_summary(store, forge, workspace)),
            )
            .await,
        );
    }
    // One failed read fails the project, so the phone keeps last-known icons
    // instead of clearing them.
    rows.into_iter()
        .filter_map(Result::transpose)
        .collect::<HostResult<Vec<_>>>()
}

async fn workspace_summary(
    store: &RuntimeStore,
    forge: &dyn ForgeProvider,
    workspace: &Workspace,
) -> HostResult<Option<Value>> {
    let linked = store
        .find_linked_review(&workspace.id)
        .await
        .map_err(|error| HostError::state(error.to_string()))?;
    let linked_number = linked
        .as_ref()
        .filter(|review| !review.dismissed)
        .and_then(|review| review.number);
    let dismissed = linked
        .filter(|review| review.dismissed)
        .and_then(|review| review.number);
    let review = match linked_number {
        Some(number) => forge.review_by_number(number).await?,
        None => {
            let Some(branch) = workspace_lookup_branch(workspace).await else {
                return Ok(None);
            };
            forge
                .review_for_branch(&branch)
                .await?
                .filter(|review| review.is_open() && Some(review.number) != dismissed)
        }
    };
    let Some(review) = review else {
        return Ok(None);
    };
    let checks = forge.checks(review.number).await;
    let counts = count_classified_checks(checks.iter().map(classify_check));
    Ok(Some(review_summary_json(
        &workspace.id,
        &review.to_json(),
        &counts,
    )))
}
