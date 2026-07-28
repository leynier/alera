use std::collections::BTreeSet;

use alera_core::runtime::{
    browser_url_allows_title_persistence, normalize_browser_title, WorkspaceTabRecord,
};
use serde_json::{json, Value};

use crate::terminal_host::host_error::HostError;

pub(super) fn normalized_capabilities(values: Vec<String>) -> BTreeSet<String> {
    values
        .into_iter()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .collect()
}

pub(super) fn tab_profile_id(tab: &WorkspaceTabRecord) -> Option<String> {
    tab.payload
        .get("browserProfileId")
        .and_then(Value::as_str)
        .map(str::to_string)
}

pub(super) fn sync_failure(page_id: &str, code: &str) -> Value {
    json!({
        "accepted": false,
        "pageId": page_id,
        "error": {"code": code, "retryable": code != "not_browser_tab"},
    })
}

pub(super) fn store_error(error: anyhow::Error) -> HostError {
    HostError::state(error.to_string())
}

pub(super) fn completed_history_url(
    url: Option<String>,
    navigation_completed: bool,
) -> Option<String> {
    url.filter(|url| navigation_completed && url != "about:blank")
}

pub(super) fn normalized_page_title(
    payload: &Value,
    raw_url: Option<&str>,
) -> (Option<String>, bool) {
    let may_persist = raw_url.is_some_and(browser_url_allows_title_persistence);
    let title = may_persist
        .then(|| {
            payload
                .get("title")
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|title| !title.is_empty())
                .map(normalize_browser_title)
                .filter(|title| !title.is_empty())
        })
        .flatten();
    (title, may_persist)
}
