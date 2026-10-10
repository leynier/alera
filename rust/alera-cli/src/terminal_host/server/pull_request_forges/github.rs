//! GitHub behind `ForgeProvider`. The commands, parsing, and failure wording
//! are the runtime's existing `gh` code (`mobile_pull_request_*`), moved behind
//! the trait without changing what runs.

use std::sync::Arc;

use async_trait::async_trait;
use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::super::mobile_pull_request_actions::{
    gh_args, Action, CommentSource as GhCommentSource, MergeMethod as GhMergeMethod,
};
use super::super::mobile_pull_request_failures::{gh_failure, gh_missing};
use super::super::mobile_pull_request_identity::GitHubIdentity;
use super::super::mobile_pull_request_links::{parse_review_reference, workspace_review_reference};
use super::super::mobile_pull_request_requests::{
    list_review_for_branch, load_checks, run_gh, view_review,
};
use super::identity::ForgeIdentity;
use super::model::{MergeMethod, Review};
use super::provider::{
    AuthStatus, CommentLocator, CommentSource, CreateInput, Created, ForgeProvider,
};
use super::runner::{ForgeOutput, ForgeRunner};

pub(crate) struct GitHubForge {
    pub(crate) identity: ForgeIdentity,
    pub(crate) github: GitHubIdentity,
    pub(crate) repo_path: String,
    /// Writes go through it, so Watch and Fix can merge on a remote host.
    pub(crate) runner: Arc<dyn ForgeRunner>,
}

/// Runs `gh` exactly as the runtime always has, for a checkout on this host.
pub(crate) struct GhRunner {
    pub(crate) cwd: String,
}

#[async_trait]
impl ForgeRunner for GhRunner {
    async fn run_with_stdin(
        &self,
        _program: &str,
        args: &[String],
        _environment: &[(String, String)],
        stdin: Option<&str>,
    ) -> HostResult<ForgeOutput> {
        if stdin.is_some() {
            return Err(HostError::state("gh requests here take no standard input."));
        }
        let args = args.iter().map(String::as_str).collect::<Vec<_>>();
        match run_gh(&self.cwd, &args).await {
            Ok((code, stdout, stderr)) => Ok(ForgeOutput {
                code,
                stdout,
                stderr,
            }),
            Err(error) if error.wire_message().starts_with("failed to run gh") => Ok(ForgeOutput {
                code: 127,
                stdout: String::new(),
                stderr: error.wire_message(),
            }),
            Err(error) => Err(error),
        }
    }
}

impl GitHubForge {
    async fn run_checked(&self, args: Vec<String>) -> HostResult<String> {
        let output = self.runner.run("gh", &args, &[]).await?;
        if output.code == 127 {
            return Err(gh_missing());
        }
        if output.code != 0 {
            return Err(gh_failure(&output.stderr, &output.stdout));
        }
        Ok(output.stdout)
    }

    async fn run_action(&self, action: Action) -> HostResult<String> {
        self.run_checked(gh_args(&action, &self.github, "")).await
    }
}

pub(crate) fn review_from_json(value: &Value) -> Review {
    let text = |key: &str| value[key].as_str().map(ToOwned::to_owned);
    Review {
        number: value["number"].as_i64().unwrap_or(0),
        title: text("title").unwrap_or_default(),
        state: match value["state"].as_str().unwrap_or("OPEN") {
            "MERGED" => "MERGED",
            "CLOSED" => "CLOSED",
            _ => "OPEN",
        },
        url: text("url").unwrap_or_default(),
        is_draft: value["isDraft"].as_bool().unwrap_or(false),
        author: text("author"),
        head_branch: text("headRefName"),
        base_branch: text("baseRefName"),
        created_at: text("createdAt"),
        mergeable: match value["mergeable"].as_str() {
            Some("MERGEABLE") => "MERGEABLE",
            Some("CONFLICTING") => "CONFLICTING",
            _ => "UNKNOWN",
        },
        head_sha: text("headSha"),
    }
}

#[async_trait]
impl ForgeProvider for GitHubForge {
    fn identity(&self) -> &ForgeIdentity {
        &self.identity
    }

    async fn auth_status(&self) -> HostResult<AuthStatus> {
        let args = ["auth", "status", "--hostname", self.github.host.as_str()];
        match run_gh(&self.repo_path, &args).await {
            Ok((0, _, _)) => Ok(AuthStatus::Authenticated),
            Ok(_) => Ok(AuthStatus::NotAuthenticated),
            Err(error) if looks_like_missing_cli(&error) => Ok(AuthStatus::CliMissing),
            Err(error) => Err(error),
        }
    }

    async fn review_by_number(&self, number: i64) -> HostResult<Option<Review>> {
        Ok(view_review(&self.repo_path, &self.github.slug, number)
            .await?
            .map(|review| review_from_json(&review)))
    }

    async fn review_for_branch(&self, branch: &str) -> HostResult<Option<Review>> {
        Ok(
            list_review_for_branch(&self.repo_path, &self.github.slug, branch)
                .await?
                .map(|review| review_from_json(&review)),
        )
    }

    async fn checks(&self, number: i64) -> Vec<Value> {
        load_checks(&self.repo_path, &self.github.slug, number).await
    }

    async fn comments(&self, number: i64) -> (Vec<Value>, bool) {
        super::super::mobile_pull_request_comments::load_comments(
            &self.repo_path,
            &self.github.host,
            &self.github.owner,
            &self.github.repo,
            number,
        )
        .await
    }

    async fn viewer(&self) -> Option<String> {
        let args = [
            "api",
            "--hostname",
            &self.github.host,
            "user",
            "--jq",
            ".login",
        ];
        let (code, stdout, _) = run_gh(&self.repo_path, &args).await.ok()?;
        let login = stdout.trim();
        (code == 0 && !login.is_empty()).then(|| login.to_string())
    }

    async fn merge_methods(&self, base_branch: Option<&str>) -> Result<Vec<String>, String> {
        super::super::mobile_pull_request_merge_methods::allowed_merge_methods(
            &self.repo_path,
            &self.github,
            base_branch,
        )
        .await
        .map(|methods| methods.into_iter().map(ToOwned::to_owned).collect())
    }

    async fn create(&self, input: &CreateInput) -> HostResult<Created> {
        let action = Action::Create {
            base: input.base.clone(),
            title: input.title.clone(),
            body: input.body.clone(),
            draft: input.draft,
        };
        let stdout = self
            .run_checked(gh_args(&action, &self.github, &input.head))
            .await?;
        let url = stdout
            .lines()
            .map(str::trim)
            .find(|line| line.starts_with("http"))
            .map(ToOwned::to_owned);
        // An unreadable URL leaves the review unlinked, as it always has.
        let number = url.as_deref().and_then(parse_review_reference).unwrap_or(0);
        Ok(Created { number, url })
    }

    async fn comment(
        &self,
        number: i64,
        body: &str,
        reply_to: Option<&CommentLocator>,
    ) -> HostResult<()> {
        self.run_action(Action::Comment {
            number,
            body: body.to_string(),
            reply_to: reply_to.map(|locator| locator.comment_id),
        })
        .await
        .map(|_| ())
    }

    async fn update_comment(
        &self,
        number: i64,
        locator: &CommentLocator,
        body: &str,
    ) -> HostResult<()> {
        self.run_action(Action::CommentUpdate {
            number,
            comment_id: locator.comment_id,
            source: match locator.source {
                CommentSource::Conversation => GhCommentSource::Conversation,
                CommentSource::ReviewSummary => GhCommentSource::ReviewSummary,
                CommentSource::ReviewThread => GhCommentSource::ReviewThread,
            },
            body: body.to_string(),
        })
        .await
        .map(|_| ())
    }

    async fn merge(
        &self,
        number: i64,
        method: MergeMethod,
        expected_head: Option<&str>,
    ) -> HostResult<()> {
        let method = match method {
            MergeMethod::MergeCommit => GhMergeMethod::MergeCommit,
            MergeMethod::Squash => GhMergeMethod::Squash,
            MergeMethod::Rebase => GhMergeMethod::Rebase,
            MergeMethod::ProviderDefault => {
                return Err(HostError::state(
                    "GitHub does not expose a provider-default merge method through gh.",
                ));
            }
        };
        let mut args = gh_args(&Action::Merge { number, method }, &self.github, "");
        if let Some(head) = expected_head {
            args.extend(["--match-head-commit".to_string(), head.to_string()]);
        }
        self.run_checked(args).await.map(|_| ())
    }

    async fn set_draft(&self, number: i64, draft: bool) -> HostResult<()> {
        self.run_action(Action::DraftStatus { number, draft })
            .await
            .map(|_| ())
    }

    async fn close(&self, number: i64) -> HostResult<()> {
        self.run_action(Action::Close { number }).await.map(|_| ())
    }

    fn review_reference(&self, input: &str) -> HostResult<i64> {
        workspace_review_reference(input, &self.github)
    }
}

fn looks_like_missing_cli(error: &HostError) -> bool {
    let message = error.wire_message().to_ascii_lowercase();
    message.contains("no such file")
        || message.contains("not found")
        || message.contains("cannot find")
        || message.contains("program not found")
}
