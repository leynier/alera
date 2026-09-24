//! The workspace-to-review link a phone can change. Writes the same
//! `LinkedReview` records the desktop keeps (`linked_review.dart`): a link
//! names the review to show, and unlinking stores a dismissal of that exact
//! review so auto-detection stops surfacing it while a different review on the
//! branch can still appear.

use alera_core::runtime::{LinkedReview, RuntimeStore};
use chrono::Utc;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::mobile_pull_request_identity::GitHubIdentity;

pub(super) const PROVIDER: &str = "github";

/// Parses `123`, `#123`, or a review URL into a number, like the desktop's
/// `parseReviewReference`.
pub(super) fn parse_review_reference(input: &str) -> Option<i64> {
    let trimmed = input.trim();
    let digits = trimmed.strip_prefix('#').unwrap_or(trimmed);
    if !digits.is_empty() && digits.bytes().all(|byte| byte.is_ascii_digit()) {
        return digits.parse().ok().filter(|number| *number > 0);
    }
    for marker in ["/pull/", "/pullrequest/", "/-/merge_requests/"] {
        if let Some((_, rest)) = trimmed.split_once(marker) {
            let number: String = rest.chars().take_while(char::is_ascii_digit).collect();
            if let Ok(number) = number.parse::<i64>() {
                return Some(number).filter(|number| *number > 0);
            }
        }
    }
    None
}

pub(super) fn workspace_review_reference(
    input: &str,
    identity: &GitHubIdentity,
) -> HostResult<i64> {
    let input = input.trim();
    let digits = input.strip_prefix('#').unwrap_or(input);
    if !digits.is_empty() && digits.bytes().all(|byte| byte.is_ascii_digit()) {
        return parse_review_reference(input)
            .ok_or_else(|| HostError::state("Enter a positive pull request number."));
    }
    let url = url::Url::parse(input)
        .map_err(|_| HostError::state("Enter a pull request number or URL."))?;
    let host = match url.port() {
        Some(port) => format!("{}:{port}", url.host_str().unwrap_or_default()),
        None => url.host_str().unwrap_or_default().to_string(),
    };
    let segments = url
        .path_segments()
        .map(Iterator::collect::<Vec<_>>)
        .unwrap_or_default();
    if !matches!(url.scheme(), "https" | "http")
        || !url.username().is_empty()
        || url.password().is_some()
        || !host.eq_ignore_ascii_case(&identity.host)
        || segments.len() < 4
        || !segments[0].eq_ignore_ascii_case(&identity.owner)
        || !segments[1].eq_ignore_ascii_case(&identity.repo)
        || segments[2] != "pull"
    {
        return Err(HostError::state(
            "The pull request URL must belong to this workspace repository.",
        ));
    }
    segments[3]
        .parse::<i64>()
        .ok()
        .filter(|number| *number > 0)
        .ok_or_else(|| HostError::state("Enter a valid pull request URL."))
}

/// The review the workspace pinned explicitly, if any.
pub(super) fn linked_number(linked: Option<&LinkedReview>) -> Option<i64> {
    linked
        .filter(|review| !review.dismissed)
        .and_then(|review| review.number)
}

/// The exact review the user unlinked, which branch detection must skip.
pub(super) fn dismissed_number(linked: Option<&LinkedReview>) -> Option<i64> {
    linked
        .filter(|review| review.dismissed)
        .and_then(|review| review.number)
}

pub(super) async fn save_link(
    store: &RuntimeStore,
    workspace_id: &str,
    number: i64,
    url: Option<String>,
    dismissed: bool,
) -> HostResult<()> {
    store
        .upsert_linked_review(LinkedReview {
            workspace_id: workspace_id.to_string(),
            dismissed,
            provider: Some(PROVIDER.to_string()),
            number: Some(number),
            url,
            linked_at: Utc::now(),
        })
        .await
        .map(|_| ())
        .map_err(|error| HostError::state(error.to_string()))
}

/// Shown in place of a review the user unlinked, so the phone can offer to
/// link it again.
pub(super) fn suggested_review_json(review: &Value) -> Value {
    json!({
        "number": review.get("number"),
        "title": review.get("title"),
        "url": review.get("url"),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn record(dismissed: bool, number: Option<i64>) -> LinkedReview {
        LinkedReview {
            workspace_id: "w".into(),
            dismissed,
            provider: Some(PROVIDER.into()),
            number,
            url: None,
            linked_at: Utc::now(),
        }
    }

    #[test]
    fn parses_numbers_hashes_and_urls() {
        assert_eq!(parse_review_reference("42"), Some(42));
        assert_eq!(parse_review_reference(" #7 "), Some(7));
        assert_eq!(
            parse_review_reference("https://github.com/leynier/alera/pull/750/files"),
            Some(750)
        );
        assert_eq!(
            parse_review_reference("https://gitlab.com/g/p/-/merge_requests/3"),
            Some(3)
        );
        assert_eq!(parse_review_reference("#0"), None);
        assert_eq!(parse_review_reference("abc"), None);
        assert_eq!(parse_review_reference(""), None);
    }

    #[test]
    fn separates_links_from_dismissals() {
        let link = record(false, Some(5));
        let dismissal = record(true, Some(5));
        let legacy = record(true, None);
        assert_eq!(linked_number(Some(&link)), Some(5));
        assert_eq!(dismissed_number(Some(&link)), None);
        assert_eq!(linked_number(Some(&dismissal)), None);
        assert_eq!(dismissed_number(Some(&dismissal)), Some(5));
        assert_eq!(dismissed_number(Some(&legacy)), None);
        assert_eq!(linked_number(None), None);
    }
}
