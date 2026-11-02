use serde_json::json;

use super::delegation_tests::delegate_payload;
use super::pull_requests::{parse_pull_request_url, CHILD_CANNOT_WATCH};
use super::test_support::{error_code, TestHarness};

const URL: &str = "https://github.com/acme/app/pull/7";

#[test]
fn pull_request_urls_name_their_forge_repository_and_number() {
    let github =
        parse_pull_request_url("https://github.com/acme/app/pull/7/files?x=1#top").unwrap();
    assert_eq!(
        (
            github.provider,
            github.repository.as_str(),
            github.number,
            github.url.as_str()
        ),
        ("github", "acme/app", 7, URL)
    );
    let gitlab =
        parse_pull_request_url("https://gitlab.com/group/sub/app/-/merge_requests/12").unwrap();
    assert_eq!(
        (gitlab.provider, gitlab.repository.as_str(), gitlab.number),
        ("gitlab", "group/sub/app", 12)
    );
    let azure = parse_pull_request_url("https://dev.azure.com/org/project/_git/app/pullrequest/34")
        .unwrap();
    assert_eq!(
        (azure.provider, azure.repository.as_str(), azure.number),
        ("azureDevOps", "org/project/app", 34)
    );
    for invalid in [
        "github.com/acme/app/pull/7",
        "https://github.com/acme/app",
        "https://github.com/acme/app/pull/x",
    ] {
        assert!(parse_pull_request_url(invalid).is_err(), "{invalid}");
    }
}

#[tokio::test]
async fn an_agent_links_watches_and_unlinks_its_chat_pull_request() {
    let harness = TestHarness::new().await;
    let chat = harness.create_chat("ws-a", "auto").await;
    harness.send_human(&chat, "live", "Open the PR.").await;
    let agent = harness.agent(&chat).await;

    let linked = harness
        .service
        .handle("linkPullRequest", &json!({"url": URL}), &agent)
        .await
        .unwrap();
    assert_eq!(linked["alreadyLinked"], false);
    assert_eq!(linked["number"], 7);
    assert!(linked.get("next").is_none());
    let again = harness
        .service
        .handle("linkPullRequest", &json!({"url": URL}), &agent)
        .await
        .unwrap();
    assert_eq!(again["alreadyLinked"], true);

    let watched = harness
        .service
        .handle("watchPullRequest", &json!({"url": URL}), &agent)
        .await
        .unwrap();
    assert_eq!(
        (watched["watching"].clone(), watched["wasWatching"].clone()),
        (json!(true), json!(false))
    );
    let listed = harness
        .service
        .handle("listPullRequests", &json!({}), &agent)
        .await
        .unwrap();
    assert_eq!(listed["pullRequests"][0]["watching"], true);
    let row = harness
        .store
        .agent_chat_pull_request(&chat, URL)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(row.watch_state.unwrap()["primed"], false);

    let unwatched = harness
        .service
        .handle("unwatchPullRequest", &json!({"url": URL}), &agent)
        .await
        .unwrap();
    assert_eq!(unwatched["wasWatching"], true);
    let unlinked = harness
        .service
        .handle("unlinkPullRequest", &json!({"url": URL}), &agent)
        .await
        .unwrap();
    assert_eq!(unlinked["wasLinked"], true);
    let unlinked = harness
        .service
        .handle("unlinkPullRequest", &json!({"url": URL}), &agent)
        .await
        .unwrap();
    assert_eq!(unlinked["wasLinked"], false);
    harness.finish().await;
}

#[tokio::test]
async fn a_delegated_child_links_with_a_report_line_but_never_watches() {
    let harness = TestHarness::new().await;
    let parent = harness.create_chat("ws-a", "auto").await;
    harness.send_human(&parent, "live", "Delegate.").await;
    let parent_agent = harness.agent(&parent).await;
    let response = harness
        .service
        .handle(
            "delegate",
            &delegate_payload("pr-child", json!({"workspace": {"workspaceId": "ws-a"}})),
            &parent_agent,
        )
        .await
        .unwrap();
    let child = response["childChatId"].as_str().unwrap().to_owned();
    let child_agent = harness.agent(&child).await;

    let linked = harness
        .service
        .handle("linkPullRequest", &json!({"url": URL}), &child_agent)
        .await
        .unwrap();
    assert_eq!(
        linked["next"],
        "End your reply with: PR <full URL>, head <SHA>, checks and reviews <state>."
    );
    let refused = harness
        .service
        .handle("watchPullRequest", &json!({"url": URL}), &child_agent)
        .await
        .unwrap_err();
    assert_eq!(error_code(&refused), "childCannotWatch");
    assert!(refused.wire_message().contains(CHILD_CANNOT_WATCH));
    // The parent may not watch for its child either: the child chat cannot be watched.
    let refused = harness
        .service
        .handle(
            "watchPullRequest",
            &json!({"url": URL, "chatId": child}),
            &parent_agent,
        )
        .await
        .unwrap_err();
    assert_eq!(error_code(&refused), "childCannotWatch");
    // The parent watches the pull request in its own chat.
    harness
        .service
        .handle("watchPullRequest", &json!({"url": URL}), &parent_agent)
        .await
        .unwrap();
    harness.finish().await;
}
