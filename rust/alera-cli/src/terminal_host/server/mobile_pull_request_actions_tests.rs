use serde_json::json;

use super::*;

fn identity() -> GitHubIdentity {
    GitHubIdentity {
        host: "github.com".into(),
        owner: "leynier".into(),
        repo: "alera".into(),
        slug: "leynier/alera".into(),
    }
}

fn args(request_type: &str, payload: Value) -> Vec<String> {
    let action = parse_action(request_type, &payload).unwrap();
    gh_args(&action, &identity(), "feat/x")
}

#[test]
fn builds_the_desktop_gh_commands() {
    assert_eq!(
        args(
            "mobile.pullRequest.comment",
            json!({"number": 7, "body": "-looks good"})
        ),
        [
            "pr",
            "comment",
            "7",
            "--repo",
            "leynier/alera",
            "--body",
            "-looks good"
        ]
    );
    assert_eq!(
        args(
            "mobile.pullRequest.merge",
            json!({"number": 7, "method": "squash"})
        ),
        ["pr", "merge", "7", "--repo", "leynier/alera", "--squash"]
    );
    assert_eq!(
        args(
            "mobile.pullRequest.draftStatus",
            json!({"number": 7, "draft": true})
        ),
        ["pr", "ready", "7", "--repo", "leynier/alera", "--undo"]
    );
    assert_eq!(
        args(
            "mobile.pullRequest.draftStatus",
            json!({"number": 7, "draft": false})
        ),
        ["pr", "ready", "7", "--repo", "leynier/alera"]
    );
    assert_eq!(
        args("mobile.pullRequest.close", json!({"number": 7})),
        ["pr", "close", "7", "--repo", "leynier/alera"]
    );
}

#[test]
fn replies_to_a_review_thread_through_the_replies_endpoint() {
    assert_eq!(
        args(
            "mobile.pullRequest.comment",
            json!({"number": 7, "body": "@x done", "replyToCommentId": 99})
        ),
        [
            "api",
            "--hostname",
            "github.com",
            "--method",
            "POST",
            "repos/leynier/alera/pulls/7/comments/99/replies",
            "--raw-field",
            "body=@x done"
        ]
    );
}

#[test]
fn edits_each_comment_source_through_its_endpoint() {
    let edit = |source: &str| {
        args(
            "mobile.pullRequest.commentUpdate",
            json!({"number": 7, "commentId": 5, "source": source, "body": "new"}),
        )
    };
    assert_eq!(
        edit("conversation")[4..6],
        ["PATCH", "repos/leynier/alera/issues/comments/5"]
    );
    assert_eq!(
        edit("reviewSummary")[4..6],
        ["PUT", "repos/leynier/alera/pulls/7/reviews/5"]
    );
    assert_eq!(
        edit("reviewThread")[4..6],
        ["PATCH", "repos/leynier/alera/pulls/comments/5"]
    );
}

#[test]
fn creates_from_the_current_branch() {
    assert_eq!(
        args(
            "mobile.pullRequest.create",
            json!({"baseBranch": " main ", "title": " Add X ", "body": "Why", "draft": true})
        ),
        [
            "pr",
            "create",
            "--repo",
            "leynier/alera",
            "--base",
            "main",
            "--head",
            "feat/x",
            "--title",
            "Add X",
            "--body",
            "Why",
            "--draft"
        ]
    );
}

#[test]
fn rejects_malformed_payloads() {
    let fails = |request_type: &str, payload: Value| parse_action(request_type, &payload).is_err();
    assert!(fails(
        "mobile.pullRequest.comment",
        json!({"number": 7, "body": "  "})
    ));
    assert!(fails(
        "mobile.pullRequest.comment",
        json!({"number": 0, "body": "x"})
    ));
    assert!(fails(
        "mobile.pullRequest.merge",
        json!({"number": 7, "method": "providerDefault"})
    ));
    assert!(fails(
        "mobile.pullRequest.merge",
        json!({"number": 7, "method": "fast"})
    ));
    assert!(fails(
        "mobile.pullRequest.draftStatus",
        json!({"number": 7})
    ));
    assert!(fails(
        "mobile.pullRequest.commentUpdate",
        json!({"number": 7, "commentId": 1, "source": "x", "body": "b"})
    ));
    assert!(fails(
        "mobile.pullRequest.create",
        json!({"baseBranch": "main", "title": " "})
    ));
    assert!(fails(
        "mobile.pullRequest.create",
        json!({"baseBranch": "", "title": "t"})
    ));
    assert!(fails("mobile.pullRequest.unlink", json!({})));
    assert!(fails("mobile.pullRequest.rebase", json!({})));
}

#[test]
fn parses_link_and_unlink() {
    assert_eq!(
        parse_action("mobile.pullRequest.link", &json!({"reference": "#12"})).unwrap(),
        Action::Link {
            reference: "#12".into()
        }
    );
    assert_eq!(
        parse_action(
            "mobile.pullRequest.unlink",
            &json!({"number": 12, "url": "u"})
        )
        .unwrap(),
        Action::Unlink {
            number: 12,
            url: Some("u".into())
        }
    );
}

#[test]
fn a_workspace_runs_one_write_at_a_time() {
    let first = BusyGuard::acquire("busy-test").unwrap();
    let second = BusyGuard::acquire("busy-test").err().unwrap();
    assert_eq!(second.wire_response(1)["errorCode"], "pullRequestBusy");
    assert!(BusyGuard::acquire("busy-test-other").is_ok());
    drop(first);
    assert!(BusyGuard::acquire("busy-test").is_ok());
}
