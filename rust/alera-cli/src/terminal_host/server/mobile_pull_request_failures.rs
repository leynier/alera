//! Turns a failed `gh` call from a mobile pull request action into the error a
//! phone shows. The wording follows the desktop forge layer
//! (`github_cli_failures.dart`), and the additive `errorCode` lets a newer
//! phone react without matching text.

use serde_json::json;

use crate::terminal_host::host_error::HostError;

pub(super) fn gh_failure(stderr: &str, stdout: &str) -> HostError {
    let detail = if stderr.trim().is_empty() {
        stdout.trim()
    } else {
        stderr.trim()
    };
    let (code, message) = classify(detail);
    HostError::conflict(code, message, json!({ "detail": detail }))
}

pub(super) fn gh_missing() -> HostError {
    HostError::conflict(
        "ghMissing",
        "Install and authenticate the GitHub CLI (gh) on the paired computer.",
        json!({}),
    )
}

fn classify(detail: &str) -> (&'static str, String) {
    let lower = detail.to_lowercase();
    if lower.contains("not logged")
        || lower.contains("authentication")
        || lower.contains("gh auth login")
    {
        return (
            "ghNotAuthenticated",
            "Sign in with gh auth login on the paired computer.".to_string(),
        );
    }
    if let Some(message) = disallowed_merge_method_message(&lower) {
        return ("mergeMethodNotAllowed", message.to_string());
    }
    if lower.contains("already exists") || lower.contains("a pull request for branch") {
        return (
            "alreadyExists",
            "A pull request already exists for this branch.".to_string(),
        );
    }
    if lower.contains("no commits between") {
        return (
            "nothingToCompare",
            "There are no commits between the base branch and this branch.".to_string(),
        );
    }
    if lower.contains("must first push")
        || lower.contains("head sha can't be blank")
        || lower.contains("head ref must be a branch")
        || lower.contains("could not find any commits")
    {
        return (
            "noUpstream",
            "Push this branch before creating a pull request.".to_string(),
        );
    }
    if lower.contains("not mergeable")
        || lower.contains("merge conflict")
        || lower.contains("base branch policy prohibits")
    {
        return (
            "mergeBlocked",
            "GitHub cannot merge this pull request yet. Resolve conflicts and required checks first."
                .to_string(),
        );
    }
    let message = if detail.is_empty() {
        "The GitHub CLI failed.".to_string()
    } else {
        detail.to_string()
    };
    ("ghFailed", message)
}

fn disallowed_merge_method_message(lower: &str) -> Option<&'static str> {
    if lower.contains("merge commits are not allowed") {
        return Some(
            "Merge commits are not allowed on this repository. Use squash and merge or rebase and merge instead.",
        );
    }
    if lower.contains("squash merges are not allowed")
        || lower.contains("squash merging is not allowed")
    {
        return Some(
            "Squash and merge is not allowed on this repository. Choose a merge method that the repository permits.",
        );
    }
    if lower.contains("rebase merges are not allowed")
        || lower.contains("rebase merging is not allowed")
    {
        return Some(
            "Rebase and merge is not allowed on this repository. Choose a merge method that the repository permits.",
        );
    }
    if lower.contains("merge method")
        && (lower.contains("not allowed") || lower.contains("is disabled"))
    {
        return Some(
            "That merge method is not allowed on this repository. Choose a method enabled in the repository settings or branch ruleset.",
        );
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn code_of(stderr: &str) -> String {
        gh_failure(stderr, "").wire_response(1)["errorCode"]
            .as_str()
            .unwrap()
            .to_string()
    }

    #[test]
    fn classifies_known_gh_failures() {
        assert_eq!(
            code_of("To get started with GitHub CLI, please run:  gh auth login"),
            "ghNotAuthenticated"
        );
        assert_eq!(
            code_of("GraphQL: Merge commits are not allowed on this repository"),
            "mergeMethodNotAllowed"
        );
        assert_eq!(
            code_of("a pull request for branch \"x\" into branch \"main\" already exists"),
            "alreadyExists"
        );
        assert_eq!(
            code_of("GraphQL: No commits between main and feat (createPullRequest)"),
            "nothingToCompare"
        );
        assert_eq!(
            code_of("GraphQL: Head sha can't be blank, Base sha can't be blank"),
            "noUpstream"
        );
        assert_eq!(
            code_of("Pull request #3 is not mergeable: the merge commit cannot be cleanly created"),
            "mergeBlocked"
        );
        assert_eq!(code_of("something odd"), "ghFailed");
    }

    #[test]
    fn unknown_failures_keep_the_gh_text_and_fall_back_to_stdout() {
        let error = gh_failure("", "HTTP 422: Validation Failed");
        assert_eq!(error.wire_message(), "HTTP 422: Validation Failed");
        assert_eq!(gh_failure("", "").wire_message(), "The GitHub CLI failed.");
    }
}
