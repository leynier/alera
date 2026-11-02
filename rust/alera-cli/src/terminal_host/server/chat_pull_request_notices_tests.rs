use serde_json::{json, Value};

use super::chat_pull_request_notices::{start_state, step, COMMENT_ONLY_LIMIT, READ_FAILURE_LIMIT};

const URL: &str = "https://github.com/acme/app/pull/7";

fn snapshot(review: Value) -> Value {
    let mut base = json!({"number": 7, "state": "OPEN", "headSha": "abcdef123", "author": "owner",
        "baseRefName": "main", "mergeable": "MERGEABLE", "checks": [], "comments": []});
    for (key, value) in review.as_object().unwrap() {
        base[key] = value.clone();
    }
    json!({"authStatus": "authenticated", "provider": "github", "review": base})
}

fn comment(id: i64, author: &str, body: &str) -> Value {
    json!({"id": id, "author": author, "body": body, "path": "src/lib.rs", "url": format!("{URL}#c{id}")})
}

#[test]
fn existing_comments_never_wake_and_new_ones_use_the_t3_notice() {
    let state = start_state(None, None);
    let first = snapshot(json!({"comments": [comment(1, "rev", "old")]}));
    let primed = step(7, URL, &state, Ok(&first));
    assert_eq!(primed.notice, None);
    let next = snapshot(json!({"comments": [comment(1, "rev", "old"),
        comment(2, "rev", "Please <!-- hidden --> rename\n  this."), comment(3, "owner", "mine")]}));
    let woke = step(7, URL, &primed.state, Ok(&next));
    assert_eq!(
        woke.notice.as_deref().unwrap(),
        "Update on pull request #7 (https://github.com/acme/app/pull/7), which Alera is watching for you:\n- 1 new comment:\n  - rev on src/lib.rs: \"Please rename this.\" https://github.com/acme/app/pull/7#c2\n\nLook into each item and act on it as your task requires. This PR stays linked and watched, so do not link, watch, or list it again. End your turn when you are done, and Alera wakes you on the next change. When you hand the work back to the user, call unwatch_pull_request first so the chat returns to their inbox."
    );
    assert!(!woke.stop);
}

#[test]
fn checks_and_conflicts_are_told_once_per_head() {
    let state = step(7, URL, &start_state(None, None), Ok(&snapshot(json!({})))).state;
    let failed = snapshot(
        json!({"checks": [{"name": "test", "bucket": "fail", "url": "https://ci/1"},
        {"name": "lint", "bucket": "cancel", "url": ""}], "mergeable": "CONFLICTING"}),
    );
    let woke = step(7, URL, &state, Ok(&failed));
    let notice = woke.notice.unwrap();
    assert!(
        notice.contains("- Checks failed on abcdef1:\n  - test https://ci/1\n  - lint (cancel)")
    );
    assert!(notice.contains("- The branch now conflicts with main."));
    assert_eq!(step(7, URL, &woke.state, Ok(&failed)).notice, None);
    let pushed =
        snapshot(json!({"headSha": "9999999aaa", "checks": [{"name": "test", "bucket": "pass"}]}));
    let green = step(7, URL, &woke.state, Ok(&pushed));
    assert!(green
        .notice
        .unwrap()
        .contains("- All 1 check passed on 9999999."));
}

#[test]
fn ten_comment_only_notices_stop_the_watch() {
    let mut state = step(7, URL, &start_state(None, None), Ok(&snapshot(json!({})))).state;
    let mut comments = Vec::new();
    for index in 1..=COMMENT_ONLY_LIMIT as i64 {
        comments.push(comment(index, "rev", "again"));
        let next = step(
            7,
            URL,
            &state,
            Ok(&snapshot(json!({"comments": comments.clone()}))),
        );
        assert_eq!(next.stop, index == COMMENT_ONLY_LIMIT as i64);
        if next.stop {
            assert!(next.notice.unwrap().ends_with(
                "Alera stopped watching after 10 comment-only updates in a row. Call watch_pull_request to watch it again."
            ));
        }
        state = next.state;
    }
}

#[test]
fn eight_failed_reads_stop_with_a_notice_and_close_or_merge_stop_the_watch() {
    let mut state = start_state(None, None);
    for attempt in 1..=READ_FAILURE_LIMIT {
        let next = step(7, URL, &state, Err(()));
        assert_eq!(next.stop, attempt == READ_FAILURE_LIMIT);
        state = next.state;
        if attempt == READ_FAILURE_LIMIT {
            assert_eq!(next.notice.unwrap(), "Alera stopped watching pull request #7 (https://github.com/acme/app/pull/7) because it failed to read it from the host 8 times in a row. Check it yourself, and call watch_pull_request to watch it again.");
        }
    }
    let unauthenticated = json!({"authStatus": "unauthenticated", "review": null});
    assert_eq!(
        step(7, URL, &start_state(None, None), Ok(&unauthenticated)).state["readFailures"],
        1
    );
    let closed = step(
        7,
        URL,
        &start_state(None, None),
        Ok(&snapshot(json!({"state": "CLOSED"}))),
    );
    assert!(closed.stop);
    assert_eq!(closed.notice.unwrap(), "Pull request #7 (https://github.com/acme/app/pull/7) was closed, so Alera stopped watching it. Call watch_pull_request if it reopens.");
    let merged = step(
        7,
        URL,
        &start_state(None, None),
        Ok(&snapshot(json!({"state": "MERGED"}))),
    );
    assert!(merged.stop);
    assert_eq!(merged.notice, None);
}
