//! GitHub-native pull request stacks through `gh api` and the `gh-stack`
//! extension, ported from the desktop's `github_stack_actions.dart` and
//! `github_stack_mappers.dart`. Stacks exist only on GitHub, as on desktop.

use std::sync::Arc;

use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::super::mobile_pull_request_identity::GitHubIdentity;
use super::identity::ForgeKind;
use super::model::{forge_failure, provider_unavailable, MergeMethod};
use super::runner::{ForgeOutput, ForgeRunner};

pub(crate) struct GitHubStacks {
    pub(crate) github: GitHubIdentity,
    pub(crate) runner: Arc<dyn ForgeRunner>,
}

fn looks_missing(output: &ForgeOutput) -> bool {
    let combined = format!("{} {}", output.stdout, output.stderr).to_ascii_lowercase();
    output.code == 127
        || combined.contains("command not found")
        || combined.contains("is not recognized")
        || combined.contains("no such file")
}

fn looks_like_missing_extension(output: &ForgeOutput) -> bool {
    let combined = format!("{}\n{}", output.stdout, output.stderr).to_ascii_lowercase();
    combined.contains("unknown command \"stack\"")
        || combined.contains("unknown command 'stack'")
        || combined.contains("'stack' is not a gh command")
        || combined.contains("extension stack not found")
        || combined.contains("gh-stack extension was not found")
}

fn missing_extension() -> HostError {
    HostError::conflict(
        "provider_unavailable",
        "Install and authenticate the gh-stack extension (gh extension install github/gh-stack) on the computer that owns this checkout.",
        json!({ "provider": "github", "cli": "gh-stack" }),
    )
}

fn classify(output: &ForgeOutput) -> HostError {
    if looks_missing(output) {
        return provider_unavailable(ForgeKind::GitHub, false);
    }
    if looks_like_missing_extension(output) {
        return missing_extension();
    }
    let lower = output.stderr.to_ascii_lowercase();
    if lower.contains("not logged")
        || lower.contains("authentication")
        || lower.contains("gh auth login")
    {
        return provider_unavailable(ForgeKind::GitHub, true);
    }
    forge_failure(ForgeKind::GitHub, &output.stderr, &output.stdout)
}

impl GitHubStacks {
    fn ensure_supported_host(&self) -> HostResult<()> {
        if self.github.host.contains(':') {
            return Err(HostError::state(
                "GitHub Enterprise Server hosts with custom HTTPS ports are not supported by the gh CLI. Use a standard HTTPS hostname without a port.",
            ));
        }
        Ok(())
    }

    fn repository_url(&self) -> String {
        format!(
            "https://{}/{}/{}",
            self.github.host, self.github.owner, self.github.repo
        )
    }

    async fn api(&self, endpoint: String) -> HostResult<Option<Value>> {
        self.ensure_supported_host()?;
        let args = vec![
            "api".to_string(),
            "--hostname".to_string(),
            self.github.host.clone(),
            endpoint,
        ];
        let output = self.runner.run("gh", &args, &[]).await?;
        if output.code != 0 {
            let lower = output.stderr.to_ascii_lowercase();
            if !looks_missing(&output) && (lower.contains("404") || lower.contains("not found")) {
                return Ok(None);
            }
            return Err(classify(&output));
        }
        serde_json::from_str(output.stdout.trim())
            .map(Some)
            .map_err(|_| HostError::state("Unexpected GitHub stack response."))
    }

    async fn run_stack(&self, args: Vec<String>) -> HostResult<()> {
        self.ensure_supported_host()?;
        let output = self.runner.run("gh", &args, &[]).await?;
        if output.code == 0 {
            return Ok(());
        }
        Err(classify(&output))
    }

    /// Whether `gh extension list` names the gh-stack extension.
    pub(crate) async fn extension_installed(&self) -> bool {
        let args = ["extension", "list"].map(String::from);
        match self.runner.run("gh", &args, &[]).await {
            Ok(output) if output.code == 0 => {
                output.stdout.to_ascii_lowercase().contains("gh-stack")
            }
            _ => false,
        }
    }

    /// The stack that holds [review_number], or `None` when it is in none.
    pub(crate) async fn stack_for_review(&self, review_number: i64) -> HostResult<Option<Value>> {
        let endpoint = format!(
            "repos/{}/{}/stacks?pull_request={review_number}",
            self.github.owner, self.github.repo
        );
        let Some(found) = self.api(endpoint).await? else {
            return Ok(None);
        };
        let entries = found
            .as_array()
            .ok_or_else(|| HostError::state("Unexpected GitHub stack search response."))?;
        let Some(first) = entries.first() else {
            return Ok(None);
        };
        let number = first["number"]
            .as_i64()
            .filter(|number| *number > 0)
            .ok_or_else(|| HostError::state("GitHub returned a stack without a valid number."))?;
        self.stack_by_number(number).await
    }

    pub(crate) async fn stack_by_number(&self, number: i64) -> HostResult<Option<Value>> {
        let endpoint = format!(
            "repos/{}/{}/stacks/{number}",
            self.github.owner, self.github.repo
        );
        match self.api(endpoint).await? {
            Some(stack) if stack.is_object() => Ok(Some(map_stack(&stack, &self.repository_url()))),
            Some(_) => Err(HostError::state("Unexpected GitHub stack response.")),
            None => Ok(None),
        }
    }

    /// `gh stack link`: a new stack from [numbers] (bottom to top), or those
    /// numbers appended to [stack_number].
    pub(crate) async fn link(
        &self,
        numbers: &[i64],
        stack_number: Option<i64>,
        base_branch: Option<&str>,
    ) -> HostResult<Value> {
        let mut args = vec!["stack".to_string(), "link".to_string()];
        args.extend(stack_number.map(|number| number.to_string()));
        args.extend(numbers.iter().map(i64::to_string));
        if let Some(base) = base_branch.map(str::trim).filter(|base| !base.is_empty()) {
            args.extend(["--base".to_string(), base.to_string()]);
        }
        self.run_stack(args).await?;
        let mut stack = match numbers.last() {
            Some(last) => self.stack_for_review(*last).await?,
            None => None,
        };
        if stack.is_none() {
            if let Some(number) = stack_number {
                stack = self.stack_by_number(number).await?;
            }
        }
        stack.ok_or_else(|| {
            HostError::state(
                "The stack was linked but GitHub did not return it yet. Refresh and try again.",
            )
        })
    }

    /// Atomically merges the stack through [review_number].
    pub(crate) async fn merge(&self, review_number: i64, method: MergeMethod) -> HostResult<()> {
        let method = match method {
            MergeMethod::MergeCommit => "merge",
            MergeMethod::Squash => "squash",
            MergeMethod::Rebase => "rebase",
            MergeMethod::ProviderDefault => {
                return Err(HostError::state(
                    "GitHub stacks require an explicit merge method.",
                ));
            }
        };
        let args = [
            "stack",
            "merge",
            &review_number.to_string(),
            "--yes",
            "--merge-method",
            method,
        ]
        .map(String::from)
        .to_vec();
        self.run_stack(args).await
    }
}

/// The stacks REST response in a provider-neutral shape, bottom layer first,
/// like `mapGitHubStack`.
pub(crate) fn map_stack(stack: &Value, repository_url: &str) -> Value {
    let entries = stack["pull_requests"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|entry| entry.is_object())
        .enumerate()
        .map(|(index, review)| {
            json!({
                "position": index + 1,
                "review": map_stack_review(review, repository_url),
            })
        })
        .collect::<Vec<_>>();
    json!({
        "number": stack["number"].as_i64().unwrap_or(0),
        "baseBranch": text(&stack["base"], "ref").unwrap_or_default(),
        "open": stack["open"].as_bool().unwrap_or(false),
        "createdAt": text(stack, "created_at"),
        "entries": entries,
    })
}

fn map_stack_review(review: &Value, repository_url: &str) -> Value {
    let number = review["number"].as_i64().unwrap_or(0);
    let head = text(&review["head"], "ref");
    let draft = review["draft"].as_bool().unwrap_or(false);
    let state = if text(review, "merged_at").is_some() {
        "MERGED"
    } else if text(review, "state").is_some_and(|state| state.eq_ignore_ascii_case("closed")) {
        "CLOSED"
    } else {
        "OPEN"
    };
    json!({
        "number": number,
        "title": text(review, "title")
            .or_else(|| head.clone())
            .unwrap_or_else(|| format!("Pull Request #{number}")),
        "state": state,
        "isDraft": state == "OPEN" && draft,
        "url": text(review, "html_url").unwrap_or_else(|| format!("{repository_url}/pull/{number}")),
        "createdAt": text(review, "created_at"),
        "author": text(&review["user"], "login"),
        "baseRefName": text(&review["base"], "ref"),
        "headRefName": head,
        "headSha": text(&review["head"], "sha"),
    })
}

fn text(value: &Value, key: &str) -> Option<String> {
    value[key]
        .as_str()
        .map(str::trim)
        .filter(|text| !text.is_empty())
        .map(ToOwned::to_owned)
}
