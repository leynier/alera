//! Azure DevOps pull requests through `az` and its azure-devops extension,
//! ported from the desktop's `azure_devops_forge_provider.dart`,
//! `azure_devops_review_actions.dart`, `azure_devops_review_comments.dart`, and
//! `azure_devops_cli_failures.dart`. Checks are the pull request's policy
//! evaluations.

use std::sync::Arc;

use async_trait::async_trait;
use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::identity::{ForgeIdentity, ForgeKind};
use super::mappers::{
    azure_check, azure_comments, azure_reply_body, azure_review, azure_thread_body,
};
use super::model::{
    fixed_merge_methods, forge_failure, newest, provider_unavailable, MergeMethod, Review,
};
use super::provider::{
    foreign_review_url, plain_review_number, AuthStatus, CommentLocator, CreateInput, Created,
    ForgeProvider,
};
use super::runner::{ForgeOutput, ForgeRunner};

pub(crate) struct AzureDevOpsForge {
    pub(crate) identity: ForgeIdentity,
    pub(crate) runner: Arc<dyn ForgeRunner>,
}

pub(crate) fn looks_missing(output: &ForgeOutput) -> bool {
    let combined = format!("{} {}", output.stdout, output.stderr).to_ascii_lowercase();
    output.code == 127
        || combined.contains("command not found")
        || combined.contains("is not recognized")
        || combined.contains("no such file")
        || combined.contains("'repos' is misspelled")
        || combined.contains("az extension add")
}

fn mentions_not_found(stderr: &str) -> bool {
    let lower = stderr.to_ascii_lowercase();
    lower.contains("does not exist") || lower.contains("not found") || lower.contains("tf401180")
}

impl AzureDevOpsForge {
    fn org(&self) -> String {
        self.identity.azure_org_url()
    }

    fn project(&self) -> HostResult<String> {
        self.identity
            .project
            .clone()
            .filter(|project| !project.is_empty())
            .ok_or_else(|| {
                HostError::state(
                    "The Azure DevOps project could not be determined from the remote.",
                )
            })
    }

    async fn run(&self, args: Vec<String>, allow_not_found: bool) -> HostResult<Option<String>> {
        let output = self.runner.run("az", &args, &[]).await?;
        if output.code == 0 {
            return Ok(Some(output.stdout));
        }
        if looks_missing(&output) {
            return Err(provider_unavailable(ForgeKind::AzureDevOps, false));
        }
        if allow_not_found && mentions_not_found(&output.stderr) {
            return Ok(None);
        }
        let lower = output.stderr.to_ascii_lowercase();
        if lower.contains("az login") || lower.contains("not logged in") {
            return Err(provider_unavailable(ForgeKind::AzureDevOps, true));
        }
        Err(forge_failure(
            ForgeKind::AzureDevOps,
            &output.stderr,
            &output.stdout,
        ))
    }

    async fn run_json(&self, args: Vec<String>, allow_not_found: bool) -> HostResult<Value> {
        let Some(output) = self.run(args, allow_not_found).await? else {
            return Ok(Value::Null);
        };
        let trimmed = output.trim();
        if trimmed.is_empty() {
            return Ok(Value::Null);
        }
        serde_json::from_str(trimmed)
            .map_err(|_| HostError::state(format!("Unexpected az output: {trimmed}")))
    }

    fn pr_args(&self, verb: &str, extra: &[&str]) -> Vec<String> {
        let mut args = vec!["repos", "pr", verb]
            .into_iter()
            .map(String::from)
            .collect::<Vec<_>>();
        args.extend(extra.iter().map(|value| value.to_string()));
        args
    }

    fn update_args(&self, number: i64, extra: &[&str]) -> Vec<String> {
        let number = number.to_string();
        let org = self.org();
        let mut args = vec!["--id", &number, "--organization", &org];
        args.extend_from_slice(extra);
        self.pr_args("update", &args)
    }

    /// `az devops invoke` against a pull request resource. The body travels
    /// in a temporary file, as the desktop does, and is removed afterwards.
    async fn invoke(
        &self,
        resource: &str,
        route: &[String],
        method: &str,
        body: Option<&Value>,
    ) -> HostResult<Value> {
        let file = body.map(|body| {
            let path = std::env::temp_dir().join(format!("alera-pr-{}.json", uuid::Uuid::new_v4()));
            std::fs::write(&path, body.to_string()).map(|_| path)
        });
        let file = file
            .transpose()
            .map_err(|error| HostError::state(format!("Could not write the request: {error}")))?;
        let mut args = ["devops", "invoke", "--area", "git", "--resource", resource]
            .map(String::from)
            .to_vec();
        args.push("--route-parameters".into());
        args.extend(route.iter().cloned());
        args.extend(["--http-method", method, "--api-version", "7.1"].map(String::from));
        if let Some(path) = &file {
            args.extend(["--in-file".to_string(), path.to_string_lossy().into_owned()]);
        }
        args.extend(["--organization".to_string(), self.org()]);
        args.extend(["--output", "json"].map(String::from));
        let result = self.run_json(args, false).await;
        if let Some(path) = file {
            let _ = std::fs::remove_file(path);
        }
        result
    }

    fn thread_route(&self, number: i64) -> HostResult<Vec<String>> {
        Ok(vec![
            format!("project={}", self.project()?),
            format!("repositoryId={}", self.identity.repo),
            format!("pullRequestId={number}"),
        ])
    }

    /// The thread that owns [locator]. Comment ids repeat across threads, so
    /// the lookup only succeeds when exactly one thread has that id.
    async fn thread_id(&self, number: i64, locator: &CommentLocator) -> HostResult<String> {
        if let Some(id) = locator.thread_id.as_deref().filter(|id| !id.is_empty()) {
            return Ok(id.to_string());
        }
        let (comments, _) = self.comments(number).await;
        let mut owners = comments
            .iter()
            .filter(|comment| comment["id"].as_i64() == Some(locator.comment_id))
            .filter_map(|comment| comment["threadId"].as_str());
        match (owners.next(), owners.next()) {
            (Some(thread), None) => Ok(thread.to_string()),
            _ => Err(HostError::state(
                "The Azure DevOps comment thread could not be determined. Pass its threadId.",
            )),
        }
    }
}

#[async_trait]
impl ForgeProvider for AzureDevOpsForge {
    fn identity(&self) -> &ForgeIdentity {
        &self.identity
    }

    async fn auth_status(&self) -> HostResult<AuthStatus> {
        let args = ["account", "show", "--output", "json"].map(String::from);
        let output = self.runner.run("az", &args, &[]).await?;
        Ok(if output.code == 0 {
            AuthStatus::Authenticated
        } else if looks_missing(&output) {
            AuthStatus::CliMissing
        } else {
            AuthStatus::NotAuthenticated
        })
    }

    async fn review_by_number(&self, number: i64) -> HostResult<Option<Review>> {
        let number = number.to_string();
        let org = self.org();
        let args = self.pr_args(
            "show",
            &["--id", &number, "--organization", &org, "--output", "json"],
        );
        let value = self.run_json(args, true).await?;
        Ok(value
            .is_object()
            .then(|| azure_review(&self.identity, &value)))
    }

    async fn review_for_branch(&self, branch: &str) -> HostResult<Option<Review>> {
        let org = self.org();
        let project = self.identity.project.clone().unwrap_or_default();
        let args = self.pr_args(
            "list",
            &[
                "--organization",
                &org,
                "--project",
                &project,
                "--repository",
                &self.identity.repo,
                "--source-branch",
                branch,
                "--status",
                "active",
                "--top",
                "100",
                "--output",
                "json",
            ],
        );
        let value = self.run_json(args, false).await?;
        Ok(newest(
            value
                .as_array()
                .into_iter()
                .flatten()
                .filter(|item| item.is_object())
                .map(|item| azure_review(&self.identity, item)),
        ))
    }

    async fn checks(&self, number: i64) -> Vec<Value> {
        let number = number.to_string();
        let org = self.org();
        let args = self.pr_args(
            "policy",
            &[
                "list",
                "--id",
                &number,
                "--organization",
                &org,
                "--output",
                "json",
            ],
        );
        match self.run_json(args, true).await {
            Ok(Value::Array(entries)) => entries
                .iter()
                .filter(|entry| entry.is_object())
                .map(|entry| azure_check(&self.identity, entry))
                .collect(),
            _ => Vec::new(),
        }
    }

    async fn comments(&self, number: i64) -> (Vec<Value>, bool) {
        let Ok(route) = self.thread_route(number) else {
            return (Vec::new(), true);
        };
        match self.invoke("pullRequestThreads", &route, "GET", None).await {
            Ok(threads) => (azure_comments(&threads), false),
            Err(_) => (Vec::new(), true),
        }
    }

    async fn viewer(&self) -> Option<String> {
        None
    }

    async fn merge_methods(&self, _base_branch: Option<&str>) -> Result<Vec<String>, String> {
        Ok(fixed_merge_methods(ForgeKind::AzureDevOps)
            .iter()
            .map(|method| method.to_string())
            .collect())
    }

    async fn create(&self, input: &CreateInput) -> HostResult<Created> {
        let org = self.org();
        let project = self.identity.project.clone().unwrap_or_default();
        let mut extra = vec![
            "--organization",
            &org,
            "--project",
            &project,
            "--repository",
            &self.identity.repo,
            "--source-branch",
            &input.head,
            "--target-branch",
            &input.base,
            "--title",
            &input.title,
            "--description",
            &input.body,
        ];
        if input.draft {
            extra.extend(["--draft", "true"]);
        }
        extra.extend(["--output", "json"]);
        let value = self.run_json(self.pr_args("create", &extra), false).await?;
        if !value.is_object() {
            return Err(HostError::state(
                "The pull request was created but could not be read back.",
            ));
        }
        let review = azure_review(&self.identity, &value);
        Ok(Created {
            number: review.number,
            url: Some(review.url),
        })
    }

    async fn comment(
        &self,
        number: i64,
        body: &str,
        reply_to: Option<&CommentLocator>,
    ) -> HostResult<()> {
        let mut route = self.thread_route(number)?;
        match reply_to {
            None => {
                self.invoke(
                    "pullRequestThreads",
                    &route,
                    "POST",
                    Some(&azure_thread_body(body)),
                )
                .await?;
            }
            Some(locator) => {
                route.push(format!(
                    "threadId={}",
                    self.thread_id(number, locator).await?
                ));
                let payload = azure_reply_body(body, locator.comment_id);
                self.invoke("pullRequestThreadComments", &route, "POST", Some(&payload))
                    .await?;
            }
        }
        Ok(())
    }

    async fn update_comment(
        &self,
        number: i64,
        locator: &CommentLocator,
        body: &str,
    ) -> HostResult<()> {
        let mut route = self.thread_route(number)?;
        route.push(format!(
            "threadId={}",
            self.thread_id(number, locator).await?
        ));
        route.push(format!("commentId={}", locator.comment_id));
        let payload = serde_json::json!({ "content": body });
        self.invoke("pullRequestThreadComments", &route, "PATCH", Some(&payload))
            .await
            .map(|_| ())
    }

    /// `az repos pr update` has no head guard, so the head is read again just
    /// before completing; the window between the two calls is a few seconds.
    async fn merge(
        &self,
        number: i64,
        method: MergeMethod,
        expected_head: Option<&str>,
    ) -> HostResult<()> {
        if matches!(method, MergeMethod::Rebase | MergeMethod::ProviderDefault) {
            return Err(HostError::state(
                "Azure DevOps does not support rebase and merge through its CLI.",
            ));
        }
        if let Some(expected) = expected_head {
            let current = self.review_by_number(number).await?;
            if current.and_then(|review| review.head_sha).as_deref() != Some(expected) {
                return Err(HostError::state(
                    "The pull request head changed before it could be merged.",
                ));
            }
        }
        let squash = if method == MergeMethod::Squash {
            "true"
        } else {
            "false"
        };
        let args = self.update_args(
            number,
            &[
                "--status",
                "completed",
                "--squash",
                squash,
                "--output",
                "none",
            ],
        );
        self.run(args, false).await.map(|_| ())
    }

    async fn set_draft(&self, number: i64, draft: bool) -> HostResult<()> {
        let draft = draft.to_string();
        let args = self.update_args(number, &["--draft", &draft, "--output", "none"]);
        self.run(args, false).await.map(|_| ())
    }

    async fn close(&self, number: i64) -> HostResult<()> {
        let args = self.update_args(number, &["--status", "abandoned", "--output", "none"]);
        self.run(args, false).await.map(|_| ())
    }

    /// `.../{project}/_git/{repo}/pullrequest/{n}` on the organization's host.
    fn review_reference(&self, input: &str) -> HostResult<i64> {
        if let Some(number) = plain_review_number(input) {
            return number;
        }
        let org_url = url::Url::parse(&self.org()).map_err(|_| foreign_review_url())?;
        let segments = super::provider::url_segments(input, org_url.host_str().unwrap_or(""))?;
        let modern = !org_url
            .host_str()
            .unwrap_or("")
            .ends_with("visualstudio.com");
        if modern
            && !segments
                .first()
                .is_some_and(|org| org.eq_ignore_ascii_case(&self.identity.owner))
        {
            return Err(foreign_review_url());
        }
        let git = segments
            .iter()
            .position(|segment| segment == "_git")
            .ok_or_else(foreign_review_url)?;
        let repo_matches = segments
            .get(git + 1)
            .is_some_and(|repo| repo.eq_ignore_ascii_case(&self.identity.repo));
        let project_matches = git >= 1
            && self
                .identity
                .project
                .as_deref()
                .is_some_and(|project| segments[git - 1].eq_ignore_ascii_case(project));
        if !repo_matches
            || !project_matches
            || segments.get(git + 2).map(String::as_str) != Some("pullrequest")
        {
            return Err(foreign_review_url());
        }
        segments
            .get(git + 3)
            .and_then(|number| number.parse::<i64>().ok())
            .filter(|number| *number > 0)
            .ok_or_else(|| HostError::state("Enter a valid pull request URL."))
    }
}
