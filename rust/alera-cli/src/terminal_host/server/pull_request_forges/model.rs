//! The provider-neutral shapes every forge maps into: the review object and
//! `checks[]` of the GitHub snapshot the phone, CLI, MCP, and Watch and Fix
//! already read, merge methods, and the errors a missing CLI produces.

use serde_json::{json, Value};

use crate::terminal_host::host_error::HostError;

use super::identity::ForgeKind;

/// One review as the snapshot carries it: `state` is `OPEN`, `CLOSED`, or
/// `MERGED`; `mergeable` is `MERGEABLE`, `CONFLICTING`, or `UNKNOWN`.
#[derive(Debug, Clone, Default, PartialEq)]
pub(crate) struct Review {
    pub(crate) number: i64,
    pub(crate) title: String,
    pub(crate) state: &'static str,
    pub(crate) url: String,
    pub(crate) is_draft: bool,
    pub(crate) author: Option<String>,
    pub(crate) head_branch: Option<String>,
    pub(crate) base_branch: Option<String>,
    pub(crate) created_at: Option<String>,
    pub(crate) mergeable: &'static str,
    pub(crate) head_sha: Option<String>,
}

impl Review {
    pub(crate) fn to_json(&self) -> Value {
        json!({
            "number": self.number,
            "title": self.title,
            "state": self.state,
            "url": self.url,
            "isDraft": self.is_draft,
            "author": self.author,
            "headRefName": self.head_branch,
            "baseRefName": self.base_branch,
            "createdAt": self.created_at,
            "mergeable": self.mergeable,
            "headSha": self.head_sha,
        })
    }

    pub(crate) fn is_open(&self) -> bool {
        self.state == "OPEN"
    }
}

/// The newest review, like the desktop's `pickNewestHostedReview`.
pub(crate) fn newest(reviews: impl IntoIterator<Item = Review>) -> Option<Review> {
    reviews
        .into_iter()
        .max_by(|a, b| a.created_at.as_deref().cmp(&b.created_at.as_deref()))
}

/// A check in the snapshot's shape. `bucket` uses `gh pr checks` names (`pass`,
/// `fail`, `pending`, `skipping`, `cancel`) so Watch and Fix and the summary
/// counts read every forge the same way; `state` keeps the forge's own word.
pub(crate) fn check_json(name: &str, state: &str, bucket: &str, url: Option<&str>) -> Value {
    json!({ "name": name, "state": state, "bucket": bucket, "url": url })
}

/// `(name, failed, pending)` for the summary counts, from a normalized check.
pub(crate) fn classify_check(check: &Value) -> (String, bool, bool) {
    let bucket = check["bucket"].as_str().unwrap_or("");
    (
        check["name"].as_str().unwrap_or("check").to_string(),
        matches!(bucket, "fail" | "cancel"),
        bucket == "pending",
    )
}

/// Merge methods by their wire names. `providerDefault` lets the forge's
/// project settings decide, which is GitLab's ordinary merge.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum MergeMethod {
    MergeCommit,
    Squash,
    Rebase,
    ProviderDefault,
}

impl MergeMethod {
    pub(crate) fn parse(value: &str) -> Option<Self> {
        match value {
            "mergeCommit" | "merge" | "noFastForward" => Some(Self::MergeCommit),
            "squash" => Some(Self::Squash),
            "rebase" => Some(Self::Rebase),
            "providerDefault" => Some(Self::ProviderDefault),
            _ => None,
        }
    }

    pub(crate) fn wire(self) -> &'static str {
        match self {
            Self::MergeCommit => "mergeCommit",
            Self::Squash => "squash",
            Self::Rebase => "rebase",
            Self::ProviderDefault => "providerDefault",
        }
    }
}

/// The methods a forge offers when it has no per-repository rules to read,
/// ported from the desktop providers' `allowedMergeMethods`.
pub(crate) fn fixed_merge_methods(kind: ForgeKind) -> &'static [&'static str] {
    match kind {
        ForgeKind::GitHub => &["mergeCommit", "squash", "rebase"],
        ForgeKind::GitLab => &["providerDefault", "squash"],
        ForgeKind::AzureDevOps => &["mergeCommit", "squash"],
    }
}

/// The method an automatic merge uses: provider-default first, then the first
/// one offered, like `preferredReviewMergeMethod`.
pub(crate) fn preferred_merge_method(methods: &[&str]) -> Option<MergeMethod> {
    if methods.contains(&"providerDefault") {
        return Some(MergeMethod::ProviderDefault);
    }
    methods.iter().find_map(|method| MergeMethod::parse(method))
}

/// The forge CLI is missing, its extension is missing, or nobody signed in.
pub(crate) fn provider_unavailable(kind: ForgeKind, signed_out: bool) -> HostError {
    let message = match (kind, signed_out) {
        (ForgeKind::GitHub, false) => {
            "Install and authenticate the GitHub CLI (gh) on the computer that owns this checkout."
        }
        (ForgeKind::GitHub, true) => {
            "Sign in with gh auth login on the computer that owns this checkout."
        }
        (ForgeKind::GitLab, false) => {
            "Install and authenticate the GitLab CLI (glab) on the computer that owns this checkout."
        }
        (ForgeKind::GitLab, true) => {
            "Sign in with glab auth login on the computer that owns this checkout."
        }
        (ForgeKind::AzureDevOps, false) => {
            "Install and authenticate the Azure CLI (az) with the azure-devops extension on the computer that owns this checkout."
        }
        (ForgeKind::AzureDevOps, true) => {
            "Sign in with az login on the computer that owns this checkout."
        }
    };
    HostError::conflict(
        "provider_unavailable",
        message,
        json!({ "provider": kind.wire(), "cli": kind.cli() }),
    )
}

/// A feature Alera only has for some forges, such as stacks outside GitHub.
pub(crate) fn provider_unsupported(message: impl Into<String>) -> HostError {
    HostError::conflict("provider_unsupported", message, json!({}))
}

/// A forge CLI call that failed for a reason other than a missing CLI.
pub(crate) fn forge_failure(kind: ForgeKind, stderr: &str, stdout: &str) -> HostError {
    let detail = if stderr.trim().is_empty() {
        stdout.trim()
    } else {
        stderr.trim()
    };
    let lower = detail.to_ascii_lowercase();
    if lower.contains("already exists")
        || lower.contains("another open merge request")
        || lower.contains("active pull request")
    {
        return HostError::conflict(
            "alreadyExists",
            format!("A {} already exists for this branch.", kind.review_noun()),
            json!({ "detail": detail }),
        );
    }
    let message = if detail.is_empty() {
        format!("The {} CLI ({}) failed.", kind.label(), kind.cli())
    } else {
        detail.to_string()
    };
    HostError::conflict("forgeFailed", message, json!({ "detail": detail }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prefers_the_provider_default_then_the_first_method() {
        assert_eq!(
            preferred_merge_method(fixed_merge_methods(ForgeKind::GitLab)),
            Some(MergeMethod::ProviderDefault)
        );
        assert_eq!(
            preferred_merge_method(&["squash", "rebase"]),
            Some(MergeMethod::Squash)
        );
        assert_eq!(preferred_merge_method(&[]), None);
        assert_eq!(
            MergeMethod::parse("noFastForward"),
            Some(MergeMethod::MergeCommit)
        );
        assert_eq!(MergeMethod::parse("fast"), None);
    }

    #[test]
    fn unavailable_providers_name_the_cli_to_install() {
        for kind in ForgeKind::ALL {
            for signed_out in [false, true] {
                let error = provider_unavailable(kind, signed_out);
                assert_eq!(error.wire_response(1)["errorCode"], "provider_unavailable");
                assert!(
                    error.wire_message().contains(&format!("{} ", kind.cli()))
                        || error.wire_message().contains(&format!("({})", kind.cli()))
                );
            }
        }
    }

    #[test]
    fn newest_review_wins() {
        let review = |number, created: &str| Review {
            number,
            created_at: Some(created.into()),
            ..Review::default()
        };
        let picked = newest([
            review(1, "2026-07-10T00:00:00Z"),
            review(2, "2026-07-11T00:00:00Z"),
        ]);
        assert_eq!(picked.unwrap().number, 2);
    }
}
