//! `ForgeProvider`: every pull request operation the runtime performs, one
//! implementation per forge. The snapshot, the write verbs, Ship, Watch and
//! Fix, and stacks call only this surface, so GitHub, GitLab, and Azure DevOps
//! behave the same way to every client.

use async_trait::async_trait;
use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::identity::{ForgeIdentity, ForgeKind};
use super::model::{MergeMethod, Review};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum AuthStatus {
    Authenticated,
    NotAuthenticated,
    CliMissing,
}

impl AuthStatus {
    pub(crate) fn wire(self) -> &'static str {
        match self {
            Self::Authenticated => "authenticated",
            Self::NotAuthenticated => "notAuthenticated",
            Self::CliMissing => "cliMissing",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct CreateInput {
    pub(crate) base: String,
    pub(crate) head: String,
    pub(crate) title: String,
    pub(crate) body: String,
    pub(crate) draft: bool,
}

/// What a create answered: enough to link the new review.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Created {
    pub(crate) number: i64,
    pub(crate) url: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum CommentSource {
    Conversation,
    ReviewSummary,
    ReviewThread,
}

impl CommentSource {
    pub(crate) fn parse(value: &str) -> HostResult<Self> {
        match value {
            "conversation" => Ok(Self::Conversation),
            "reviewSummary" => Ok(Self::ReviewSummary),
            "reviewThread" => Ok(Self::ReviewThread),
            other => Err(HostError::state(format!("Unknown comment source: {other}"))),
        }
    }
}

/// Addresses one comment. `thread_id` is the GitLab discussion or Azure
/// DevOps thread; GitHub does not need it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct CommentLocator {
    pub(crate) source: CommentSource,
    pub(crate) comment_id: i64,
    pub(crate) thread_id: Option<String>,
}

#[async_trait]
pub(crate) trait ForgeProvider: Send + Sync {
    fn identity(&self) -> &ForgeIdentity;

    fn kind(&self) -> ForgeKind {
        self.identity().kind
    }

    async fn auth_status(&self) -> HostResult<AuthStatus>;

    async fn review_by_number(&self, number: i64) -> HostResult<Option<Review>>;

    /// The newest open review whose head is [branch].
    async fn review_for_branch(&self, branch: &str) -> HostResult<Option<Review>>;

    /// Checks, pipelines, or policies in the snapshot's `checks[]` shape. A
    /// failed read yields nothing so one source never hides the review.
    async fn checks(&self, number: i64) -> Vec<Value>;

    /// Comments in the snapshot's shape and whether the list was cut short.
    async fn comments(&self, number: i64) -> (Vec<Value>, bool);

    /// Who is signed in, so only their own comments are editable.
    async fn viewer(&self) -> Option<String>;

    /// Wire names of the merge methods this review may use.
    async fn merge_methods(&self, base_branch: Option<&str>) -> Result<Vec<String>, String>;

    async fn create(&self, input: &CreateInput) -> HostResult<Created>;

    /// A new comment, or a reply to [reply_to].
    async fn comment(
        &self,
        number: i64,
        body: &str,
        reply_to: Option<&CommentLocator>,
    ) -> HostResult<()>;

    async fn update_comment(
        &self,
        number: i64,
        locator: &CommentLocator,
        body: &str,
    ) -> HostResult<()>;

    /// Merges, only while the head is still [expected_head] when one is given.
    async fn merge(
        &self,
        number: i64,
        method: MergeMethod,
        expected_head: Option<&str>,
    ) -> HostResult<()>;

    async fn set_draft(&self, number: i64, draft: bool) -> HostResult<()>;

    async fn close(&self, number: i64) -> HostResult<()>;

    /// The review number a link names: `123`, `#123`, or a review URL of this
    /// repository.
    fn review_reference(&self, input: &str) -> HostResult<i64>;
}

/// `123` or `#123`, shared by every forge's `review_reference`.
pub(crate) fn plain_review_number(input: &str) -> Option<HostResult<i64>> {
    let input = input.trim();
    let digits = input.strip_prefix('#').unwrap_or(input);
    if digits.is_empty() || !digits.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    Some(
        digits
            .parse::<i64>()
            .ok()
            .filter(|number| *number > 0)
            .ok_or_else(|| HostError::state("Enter a positive pull request number.")),
    )
}

/// The path segments of a review URL on [host], or an error naming the
/// repository rule.
pub(crate) fn url_segments(input: &str, host: &str) -> HostResult<Vec<String>> {
    let url = url::Url::parse(input.trim())
        .map_err(|_| HostError::state("Enter a pull request number or URL."))?;
    let url_host = match url.port() {
        Some(port) => format!("{}:{port}", url.host_str().unwrap_or_default()),
        None => url.host_str().unwrap_or_default().to_string(),
    };
    if !matches!(url.scheme(), "https" | "http")
        || !url.username().is_empty()
        || url.password().is_some()
        || !url_host.eq_ignore_ascii_case(host)
    {
        return Err(foreign_review_url());
    }
    Ok(url
        .path_segments()
        .map(|segments| segments.map(ToOwned::to_owned).collect())
        .unwrap_or_default())
}

pub(crate) fn foreign_review_url() -> HostError {
    HostError::state("The pull request URL must belong to this workspace repository.")
}
