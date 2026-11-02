//! What a chat's pull request watch tells the chat
//! (`chatOrchestrationPullRequestsV1`), ported from T3 Code's watch notices.
//! A pure step over the watch state and one review snapshot; the check
//! classifiers are Watch and Fix's (`pull_request_watch_evaluation.rs`).

use serde_json::{json, Value};

use super::pull_request_watch_evaluation::{check_failed, check_passed};

/// Comment-only notices in a row before the watch stops.
pub(crate) const COMMENT_ONLY_LIMIT: u64 = 10;
/// Failed reads in a row before the watch stops.
pub(crate) const READ_FAILURE_LIMIT: u64 = 8;
const LIST_LIMIT: usize = 10;
const BODY_LIMIT: usize = 200;

#[derive(Debug, PartialEq)]
pub(crate) struct WatchStep {
    pub state: Value,
    pub notice: Option<String>,
    /// The watch ends after this step.
    pub stop: bool,
}

/// The state a new watch starts from: the comments already there never wake
/// the chat. Watching again keeps the earlier check and conflict state.
pub(crate) fn start_state(previous: Option<&Value>, snapshot: Option<&Value>) -> Value {
    let mut state = previous.cloned().unwrap_or_else(|| json!({}));
    if !state.is_object() {
        state = json!({});
    }
    state["commentStreak"] = json!(0);
    state["readFailures"] = json!(0);
    let mut seen = seen_comments(&state);
    if let Some(review) = snapshot.map(|snapshot| &snapshot["review"]) {
        seen.extend(comments(review).iter().map(|comment| comment_id(comment)));
    }
    state["seenComments"] = json!(seen);
    state["primed"] = json!(snapshot.is_some_and(|snapshot| !snapshot["review"].is_null()));
    state
}

/// One read of the watched review: `Err` when it could not be read.
pub(crate) fn step(number: i64, url: &str, state: &Value, read: Result<&Value, ()>) -> WatchStep {
    let mut state = state.clone();
    let review = match read {
        Ok(snapshot)
            if snapshot["authStatus"] == "authenticated" && snapshot["review"].is_object() =>
        {
            &snapshot["review"]
        }
        _ => {
            let failures = state["readFailures"].as_u64().unwrap_or(0) + 1;
            state["readFailures"] = json!(failures);
            if failures < READ_FAILURE_LIMIT {
                return WatchStep {
                    state,
                    notice: None,
                    stop: false,
                };
            }
            return WatchStep {
                state,
                notice: Some(format!(
                    "Alera stopped watching pull request #{number} ({url}) because it failed to read it from the host {READ_FAILURE_LIMIT} times in a row. Check it yourself, and call watch_pull_request to watch it again."
                )),
                stop: true,
            };
        }
    };
    state["readFailures"] = json!(0);
    match review["state"].as_str() {
        Some("MERGED") => return WatchStep { state, notice: None, stop: true },
        Some("CLOSED") => {
            return WatchStep {
                state,
                notice: Some(format!(
                    "Pull request #{number} ({url}) was closed, so Alera stopped watching it. Call watch_pull_request if it reopens."
                )),
                stop: true,
            }
        }
        _ => {}
    }
    // The first good read only learns the comments already there.
    if state["primed"] != true {
        let seen: Vec<String> = comments(review).iter().map(|c| comment_id(c)).collect();
        state["seenComments"] = json!(seen);
        state["primed"] = json!(true);
    }
    let head = review["headSha"].as_str().filter(|sha| !sha.is_empty());
    if head.is_some() && state["headSha"].as_str() != head {
        // A push starts over: old check news is not repeated on the new head.
        state["headSha"] = json!(head);
        state["checksFailedNotified"] = json!(false);
        state["checksPassedNotified"] = json!(false);
        state["commentStreak"] = json!(0);
    }
    let commit = head
        .map(|sha| format!(" on {}", &sha[..sha.len().min(7)]))
        .unwrap_or_default();
    let checks = review["checks"].as_array().cloned().unwrap_or_default();
    let mut blocks = Vec::new();
    let mut other_news = false;

    let failed: Vec<&Value> = checks.iter().filter(|check| check_failed(check)).collect();
    if !failed.is_empty() && state["checksFailedNotified"] != true {
        state["checksFailedNotified"] = json!(true);
        let lines = failed.iter().map(|check| {
            let bucket = check["bucket"].as_str().unwrap_or("");
            let status = if matches!(bucket, "fail" | "failure" | "") {
                String::new()
            } else {
                format!(" ({bucket})")
            };
            let link = check["url"]
                .as_str()
                .filter(|url| !url.is_empty())
                .map(|url| format!(" {url}"))
                .unwrap_or_default();
            format!(
                "  - {}{status}{link}",
                check["name"].as_str().unwrap_or("check")
            )
        });
        blocks.push(format!(
            "- Checks failed{commit}:\n{}",
            list(lines.collect())
        ));
        other_news = true;
    } else if failed.is_empty()
        && !checks.is_empty()
        && checks.iter().all(check_passed)
        && state["checksPassedNotified"] != true
    {
        state["checksPassedNotified"] = json!(true);
        let count = checks.len();
        let noun = if count == 1 { "check" } else { "checks" };
        blocks.push(format!("- All {count} {noun} passed{commit}."));
        other_news = true;
    }

    let author = review["author"]
        .as_str()
        .unwrap_or("")
        .trim()
        .to_lowercase();
    let mut seen = seen_comments(&state);
    let mut fresh = Vec::new();
    for comment in comments(review) {
        let id = comment_id(comment);
        if seen.contains(&id) {
            continue;
        }
        seen.push(id);
        let login = comment["author"].as_str().unwrap_or("").trim();
        if !author.is_empty() && login.to_lowercase() == author {
            continue;
        }
        fresh.push(remark_line(comment));
    }
    state["seenComments"] = json!(seen);
    if !fresh.is_empty() {
        let noun = if fresh.len() == 1 {
            "comment"
        } else {
            "comments"
        };
        blocks.push(format!("- {} new {noun}:\n{}", fresh.len(), list(fresh)));
    }

    let conflicting = review["mergeable"] == "CONFLICTING";
    if conflicting && state["conflictNotified"] != true {
        let base = review["baseRefName"].as_str().unwrap_or("the base branch");
        blocks.push(format!("- The branch now conflicts with {base}."));
        other_news = true;
    }
    state["conflictNotified"] = json!(conflicting);

    if blocks.is_empty() {
        return WatchStep {
            state,
            notice: None,
            stop: false,
        };
    }
    let streak = if other_news {
        0
    } else {
        state["commentStreak"].as_u64().unwrap_or(0) + 1
    };
    state["commentStreak"] = json!(streak);
    let stop = streak >= COMMENT_ONLY_LIMIT;
    let footer = if stop {
        format!("Alera stopped watching after {COMMENT_ONLY_LIMIT} comment-only updates in a row. Call watch_pull_request to watch it again.")
    } else {
        "Look into each item and act on it as your task requires. This PR stays linked and watched, so do not link, watch, or list it again. End your turn when you are done, and Alera wakes you on the next change. When you hand the work back to the user, call unwatch_pull_request first so the chat returns to their inbox.".to_owned()
    };
    WatchStep {
        state,
        notice: Some(format!(
            "Update on pull request #{number} ({url}), which Alera is watching for you:\n{}\n\n{footer}",
            blocks.join("\n")
        )),
        stop,
    }
}

fn comments(review: &Value) -> Vec<&Value> {
    review["comments"]
        .as_array()
        .into_iter()
        .flatten()
        .collect()
}

fn comment_id(comment: &Value) -> String {
    match &comment["id"] {
        Value::String(id) if !id.is_empty() => id.clone(),
        Value::Number(id) if id.as_i64() != Some(0) => id.to_string(),
        _ => format!(
            "{}:{}:{}",
            comment["threadId"].as_str().unwrap_or(""),
            comment["author"].as_str().unwrap_or(""),
            comment["body"].as_str().unwrap_or("")
        ),
    }
}

fn seen_comments(state: &Value) -> Vec<String> {
    state["seenComments"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|id| id.as_str().map(str::to_owned))
        .collect()
}

fn remark_line(comment: &Value) -> String {
    let login = comment["author"]
        .as_str()
        .filter(|login| !login.trim().is_empty())
        .unwrap_or("someone");
    let path = comment["path"]
        .as_str()
        .filter(|path| !path.is_empty())
        .map(|path| format!(" on {path}"))
        .unwrap_or_default();
    let body = clean_body(comment["body"].as_str().unwrap_or(""));
    let said = if body.is_empty() {
        comment["state"]
            .as_str()
            .filter(|state| !state.is_empty())
            .unwrap_or("reviewed")
            .to_owned()
    } else {
        format!("\"{body}\"")
    };
    let link = comment["url"]
        .as_str()
        .filter(|url| !url.is_empty())
        .map(|url| format!(" {url}"))
        .unwrap_or_default();
    format!("  - {login}{path}: {said}{link}")
}

/// HTML comments removed, whitespace collapsed, cut to 200 characters.
fn clean_body(body: &str) -> String {
    let mut text = String::new();
    let mut rest = body;
    while let Some(start) = rest.find("<!--") {
        text.push_str(&rest[..start]);
        rest = rest[start..]
            .find("-->")
            .map(|end| &rest[start + end + 3..])
            .unwrap_or("");
    }
    text.push_str(rest);
    let text = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if text.chars().count() <= BODY_LIMIT {
        return text;
    }
    format!(
        "{}...",
        text.chars().take(BODY_LIMIT - 3).collect::<String>()
    )
}

fn list(lines: Vec<String>) -> String {
    let more = lines.len().saturating_sub(LIST_LIMIT);
    let mut shown: Vec<String> = lines.into_iter().take(LIST_LIMIT).collect();
    if more > 0 {
        shown.push(format!("  - and {more} more"));
    }
    shown.join("\n")
}
