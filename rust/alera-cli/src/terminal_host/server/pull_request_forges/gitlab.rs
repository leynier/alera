//! GitLab merge requests through `glab`, ported from the desktop's
//! `gitlab_forge_provider.dart`, `gitlab_review_actions.dart`, and
//! `gitlab_review_comments.dart`: the same argv, the same API endpoints, and
//! the same failure classification.

use std::sync::Arc;

use async_trait::async_trait;
use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::identity::{ForgeIdentity, ForgeKind};
use super::mappers::{gitlab_comments, gitlab_pipeline, gitlab_review};
use super::model::{
    fixed_merge_methods, forge_failure, newest, provider_unavailable, MergeMethod, Review,
};
use super::provider::{
    foreign_review_url, plain_review_number, url_segments, AuthStatus, CommentLocator,
    CommentSource, CreateInput, Created, ForgeProvider,
};
use super::runner::{ForgeOutput, ForgeRunner};

pub(crate) struct GitLabForge {
    pub(crate) identity: ForgeIdentity,
    pub(crate) runner: Arc<dyn ForgeRunner>,
}

/// Same as Dart's `Uri.encodeComponent`.
pub(crate) fn encode_component(value: &str) -> String {
    value
        .bytes()
        .map(|byte| match byte {
            b'A'..=b'Z'
            | b'a'..=b'z'
            | b'0'..=b'9'
            | b'-'
            | b'_'
            | b'.'
            | b'!'
            | b'~'
            | b'*'
            | b'\''
            | b'('
            | b')' => (byte as char).to_string(),
            _ => format!("%{byte:02X}"),
        })
        .collect()
}

fn looks_missing(output: &ForgeOutput) -> bool {
    let stderr = output.stderr.to_ascii_lowercase();
    output.code == 127
        || stderr.contains("command not found")
        || stderr.contains("is not recognized")
        || stderr.contains("no such file")
}

fn looks_unauthenticated(stderr: &str) -> bool {
    let lower = stderr.to_ascii_lowercase();
    lower.contains("not logged")
        || lower.contains("unauthorized")
        || lower.contains("authentication")
        || lower.contains("glab auth login")
}

impl GitLabForge {
    pub(crate) fn repo_url(&self) -> String {
        format!(
            "https://{}/{}/{}",
            self.identity.host, self.identity.owner, self.identity.repo
        )
    }

    fn project_endpoint(&self) -> String {
        format!(
            "projects/{}",
            encode_component(&format!("{}/{}", self.identity.owner, self.identity.repo))
        )
    }

    fn mr_endpoint(&self, number: i64) -> String {
        format!("{}/merge_requests/{number}", self.project_endpoint())
    }

    /// `glab api`. `glab api --hostname` rejects an authority with a port, so
    /// such a host is addressed through `GITLAB_REPO` instead.
    async fn api(
        &self,
        endpoint: &str,
        method: Option<&str>,
        fields: &[String],
        paginate: bool,
        allow_not_found: bool,
    ) -> HostResult<Option<String>> {
        let override_repo = self.identity.host.contains(':');
        let mut args = vec!["api".to_string(), endpoint.to_string()];
        if !override_repo {
            args.extend(["--hostname".to_string(), self.identity.host.clone()]);
        }
        if paginate {
            args.extend(["--paginate", "--output", "ndjson"].map(String::from));
        }
        if let Some(method) = method {
            args.extend(["--method".to_string(), method.to_string()]);
        }
        for field in fields {
            args.extend(["--raw-field".to_string(), field.clone()]);
        }
        let environment = if override_repo {
            vec![("GITLAB_REPO".to_string(), self.repo_url())]
        } else {
            Vec::new()
        };
        self.run(args, &environment, allow_not_found).await
    }

    async fn run(
        &self,
        args: Vec<String>,
        environment: &[(String, String)],
        allow_not_found: bool,
    ) -> HostResult<Option<String>> {
        let output = self.runner.run("glab", &args, environment).await?;
        if output.code == 0 {
            return Ok(Some(output.stdout));
        }
        if looks_missing(&output) {
            return Err(provider_unavailable(ForgeKind::GitLab, false));
        }
        let lower = output.stderr.to_ascii_lowercase();
        if allow_not_found && (lower.contains("404") || lower.contains("not found")) {
            return Ok(None);
        }
        if looks_unauthenticated(&output.stderr) {
            return Err(provider_unavailable(ForgeKind::GitLab, true));
        }
        Err(forge_failure(
            ForgeKind::GitLab,
            &output.stderr,
            &output.stdout,
        ))
    }

    async fn run_mr(&self, mut args: Vec<String>) -> HostResult<String> {
        args.splice(0..0, ["mr".to_string()]);
        Ok(self.run(args, &[], false).await?.unwrap_or_default())
    }

    async fn merge_request(&self, number: i64) -> HostResult<Option<Value>> {
        let Some(output) = self
            .api(&self.mr_endpoint(number), None, &[], false, true)
            .await?
        else {
            return Ok(None);
        };
        decode(&output).map(|value| value.filter(Value::is_object))
    }

    /// The discussion that owns [locator], reading it from the review when
    /// the caller did not name it.
    async fn discussion_id(&self, number: i64, locator: &CommentLocator) -> HostResult<String> {
        if let Some(id) = locator.thread_id.as_deref().filter(|id| !id.is_empty()) {
            return Ok(id.to_string());
        }
        let (comments, _) = self.comments(number).await;
        comments
            .iter()
            .find(|comment| comment["id"].as_i64() == Some(locator.comment_id))
            .and_then(|comment| comment["discussionId"].as_str())
            .map(ToOwned::to_owned)
            .ok_or_else(|| {
                HostError::state("The GitLab comment discussion could not be determined.")
            })
    }
}

pub(crate) fn decode(raw: &str) -> HostResult<Option<Value>> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Ok(None);
    }
    serde_json::from_str(trimmed)
        .map(Some)
        .map_err(|_| HostError::state(format!("Unexpected glab output: {trimmed}")))
}

pub(crate) fn decode_ndjson(raw: &str) -> HostResult<Vec<Value>> {
    raw.lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(|line| {
            serde_json::from_str(line).map_err(|_| {
                HostError::state(format!("Unexpected glab NDJSON output: {}", raw.trim()))
            })
        })
        .collect()
}

pub(crate) fn merge_request_number(output: &str) -> Option<(i64, String)> {
    let start = output.find("http")?;
    let url = output[start..].split_whitespace().next()?.to_string();
    let (_, rest) = url.split_once("/-/merge_requests/")?;
    let digits = rest
        .chars()
        .take_while(char::is_ascii_digit)
        .collect::<String>();
    Some((digits.parse().ok()?, url))
}

#[async_trait]
impl ForgeProvider for GitLabForge {
    fn identity(&self) -> &ForgeIdentity {
        &self.identity
    }

    async fn auth_status(&self) -> HostResult<AuthStatus> {
        let args = ["auth", "status", "--hostname", &self.identity.host].map(String::from);
        let output = self.runner.run("glab", &args, &[]).await?;
        Ok(if output.code == 0 {
            AuthStatus::Authenticated
        } else if looks_missing(&output) {
            AuthStatus::CliMissing
        } else {
            AuthStatus::NotAuthenticated
        })
    }

    async fn review_by_number(&self, number: i64) -> HostResult<Option<Review>> {
        Ok(self
            .merge_request(number)
            .await?
            .map(|value| gitlab_review(&value)))
    }

    async fn review_for_branch(&self, branch: &str) -> HostResult<Option<Review>> {
        let endpoint = format!(
            "{}/merge_requests?state=opened&source_branch={}&per_page=100",
            self.project_endpoint(),
            url::form_urlencoded::byte_serialize(branch.as_bytes()).collect::<String>()
        );
        let output = self.api(&endpoint, None, &[], true, false).await?;
        let records = decode_ndjson(&output.unwrap_or_default())?;
        Ok(newest(
            records
                .iter()
                .filter(|record| record.is_object())
                .map(gitlab_review),
        ))
    }

    async fn checks(&self, number: i64) -> Vec<Value> {
        match self.merge_request(number).await {
            Ok(Some(value)) if value["head_pipeline"].is_object() => {
                vec![gitlab_pipeline(&value["head_pipeline"])]
            }
            _ => Vec::new(),
        }
    }

    /// A failed read reports a cut-short list, so Watch, Fix and Merge never
    /// mistakes an unreadable conversation for a clear one.
    async fn comments(&self, number: i64) -> (Vec<Value>, bool) {
        let endpoint = format!("{}/discussions?per_page=100", self.mr_endpoint(number));
        match self.api(&endpoint, None, &[], true, false).await {
            Ok(output) => match decode_ndjson(&output.unwrap_or_default()) {
                Ok(discussions) => (gitlab_comments(&discussions), false),
                Err(_) => (Vec::new(), true),
            },
            Err(_) => (Vec::new(), true),
        }
    }

    async fn viewer(&self) -> Option<String> {
        let output = self.api("user", None, &[], false, false).await.ok()??;
        let user = decode(&output).ok()??;
        user["username"].as_str().map(ToOwned::to_owned)
    }

    async fn merge_methods(&self, _base_branch: Option<&str>) -> Result<Vec<String>, String> {
        Ok(fixed_merge_methods(ForgeKind::GitLab)
            .iter()
            .map(|method| method.to_string())
            .collect())
    }

    async fn create(&self, input: &CreateInput) -> HostResult<Created> {
        let mut args = vec![
            "create",
            "--repo",
            &self.repo_url(),
            "--source-branch",
            &input.head,
            "--target-branch",
            &input.base,
            "--title",
            &input.title,
            "--description",
            &input.body,
        ]
        .into_iter()
        .map(String::from)
        .collect::<Vec<_>>();
        if input.draft {
            args.push("--draft".into());
        }
        args.push("--yes".into());
        let stdout = self.run_mr(args).await?;
        if let Some((number, url)) = merge_request_number(&stdout) {
            return Ok(Created {
                number,
                url: Some(url),
            });
        }
        match self.review_for_branch(&input.head).await? {
            Some(review) => Ok(Created {
                number: review.number,
                url: Some(review.url),
            }),
            None => Err(HostError::state(
                "The merge request was created but could not be read back.",
            )),
        }
    }

    async fn comment(
        &self,
        number: i64,
        body: &str,
        reply_to: Option<&CommentLocator>,
    ) -> HostResult<()> {
        let endpoint = match reply_to {
            None => format!("{}/notes", self.mr_endpoint(number)),
            Some(locator) => format!(
                "{}/discussions/{}/notes",
                self.mr_endpoint(number),
                encode_component(&self.discussion_id(number, locator).await?)
            ),
        };
        let fields = [format!("body={body}")];
        self.api(&endpoint, Some("POST"), &fields, false, false)
            .await
            .map(|_| ())
    }

    async fn update_comment(
        &self,
        number: i64,
        locator: &CommentLocator,
        body: &str,
    ) -> HostResult<()> {
        let note = encode_component(&locator.comment_id.to_string());
        let endpoint = match locator.source {
            CommentSource::ReviewSummary => {
                return Err(HostError::state(
                    "GitLab does not expose pull-request review summaries as comments.",
                ));
            }
            CommentSource::ReviewThread => format!(
                "{}/discussions/{}/notes/{note}",
                self.mr_endpoint(number),
                encode_component(&self.discussion_id(number, locator).await?)
            ),
            CommentSource::Conversation => format!("{}/notes/{note}", self.mr_endpoint(number)),
        };
        let fields = [format!("body={body}")];
        self.api(&endpoint, Some("PUT"), &fields, false, false)
            .await
            .map(|_| ())
    }

    async fn merge(
        &self,
        number: i64,
        method: MergeMethod,
        expected_head: Option<&str>,
    ) -> HostResult<()> {
        if matches!(method, MergeMethod::Rebase | MergeMethod::MergeCommit) {
            return Err(HostError::state(
                "GitLab merge topology is controlled by the project settings.",
            ));
        }
        let mut args = vec![
            "merge".to_string(),
            number.to_string(),
            "--repo".into(),
            self.repo_url(),
        ];
        if method == MergeMethod::Squash {
            args.push("--squash".into());
        }
        if let Some(head) = expected_head {
            args.extend(["--sha".to_string(), head.to_string()]);
        }
        args.extend(["--auto-merge=false".to_string(), "--yes".to_string()]);
        self.run_mr(args).await.map(|_| ())
    }

    async fn set_draft(&self, number: i64, draft: bool) -> HostResult<()> {
        let args = vec![
            "update".to_string(),
            number.to_string(),
            "--repo".into(),
            self.repo_url(),
            if draft { "--draft" } else { "--ready" }.into(),
            "--yes".into(),
        ];
        self.run_mr(args).await.map(|_| ())
    }

    async fn close(&self, number: i64) -> HostResult<()> {
        let args = vec![
            "close".to_string(),
            number.to_string(),
            "--repo".into(),
            self.repo_url(),
        ];
        self.run_mr(args).await.map(|_| ())
    }

    fn review_reference(&self, input: &str) -> HostResult<i64> {
        if let Some(number) = plain_review_number(input) {
            return number;
        }
        let segments = url_segments(input, &self.identity.host)?;
        let repo_path = format!("{}/{}", self.identity.owner, self.identity.repo);
        let marker = segments
            .iter()
            .position(|segment| segment == "-")
            .filter(|index| segments.get(index + 1).map(String::as_str) == Some("merge_requests"))
            .ok_or_else(foreign_review_url)?;
        if !segments[..marker]
            .join("/")
            .eq_ignore_ascii_case(&repo_path)
        {
            return Err(foreign_review_url());
        }
        segments
            .get(marker + 2)
            .and_then(|number| number.parse::<i64>().ok())
            .filter(|number| *number > 0)
            .ok_or_else(|| HostError::state("Enter a valid merge request URL."))
    }
}
