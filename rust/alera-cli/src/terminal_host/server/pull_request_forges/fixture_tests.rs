//! The recorded `glab` and `az` output under `test/fixtures/forges/`, which
//! the desktop's Dart tests read too (`forge_shared_fixtures_test.dart`), run
//! through the Rust providers. A drift between the two ports fails here or
//! there.

use std::sync::Arc;

use serde_json::Value;

use super::azure::AzureDevOpsForge;
use super::gitlab::GitLabForge;
use super::identity::{ForgeIdentity, ForgeKind};
use super::model::Review;
use super::provider::ForgeProvider;
use super::runner::fake::{ok, FakeRunner};

macro_rules! fixture {
    ($name:literal) => {
        serde_json::from_str::<Value>(include_str!(concat!(
            "../../../../../../test/fixtures/forges/",
            $name
        )))
        .unwrap()
    };
}

fn gitlab(stdout: &str) -> (GitLabForge, Arc<FakeRunner>) {
    let runner = Arc::new(FakeRunner::new([ok(stdout)]));
    let forge = GitLabForge {
        identity: ForgeIdentity {
            kind: ForgeKind::GitLab,
            host: "gitlab.acme.test:8443".into(),
            owner: "platform/mobile".into(),
            repo: "alera".into(),
            project: None,
        },
        runner: runner.clone(),
    };
    (forge, runner)
}

fn azure(fixture: &Value) -> (AzureDevOpsForge, Arc<FakeRunner>) {
    let identity = &fixture["identity"];
    let text = |key: &str| identity[key].as_str().unwrap().to_string();
    let runner = Arc::new(FakeRunner::new([ok(fixture["stdout"].as_str().unwrap())]));
    let forge = AzureDevOpsForge {
        identity: ForgeIdentity {
            kind: ForgeKind::AzureDevOps,
            host: text("host"),
            owner: text("owner"),
            repo: text("repo"),
            project: Some(text("project")),
        },
        runner: runner.clone(),
    };
    (forge, runner)
}

/// Compares a review with the neutral expectation the Dart test also reads.
fn assert_review(review: &Review, expected: &Value) {
    let state = match (review.state, review.is_draft) {
        ("MERGED", _) => "merged",
        ("CLOSED", _) => "closed",
        (_, true) => "draft",
        _ => "open",
    };
    assert_eq!(review.number, expected["number"].as_i64().unwrap());
    assert_eq!(review.title, expected["title"].as_str().unwrap());
    assert_eq!(state, expected["state"]);
    assert_eq!(review.author.as_deref(), expected["author"].as_str());
    assert_eq!(
        review.base_branch.as_deref(),
        expected["baseBranch"].as_str()
    );
    assert_eq!(
        review.head_branch.as_deref(),
        expected["headBranch"].as_str()
    );
    assert_eq!(review.head_sha.as_deref(), expected["headSha"].as_str());
    assert_eq!(review.mergeable.to_ascii_lowercase(), expected["mergeable"]);
    assert_eq!(review.url, expected["url"].as_str().unwrap());
}

fn assert_checks(checks: &[Value], expected: &Value) {
    let expected = expected.as_array().unwrap();
    assert_eq!(checks.len(), expected.len());
    for (check, expected) in checks.iter().zip(expected) {
        assert_eq!(check["name"], expected["name"]);
        assert_eq!(check["bucket"], expected["bucket"]);
        assert_eq!(check["url"], expected["url"]);
    }
}

fn assert_comments(comments: &[Value], expected: &Value) {
    let expected = expected.as_array().unwrap();
    assert_eq!(comments.len(), expected.len());
    for (comment, expected) in comments.iter().zip(expected) {
        for key in [
            "id", "author", "body", "kind", "path", "line", "resolved", "threadId",
        ] {
            assert_eq!(comment[key], expected[key], "{key} of {comment}");
        }
    }
}

#[tokio::test]
async fn gitlab_merge_requests_and_pipelines_match_the_desktop() {
    for fixture in [
        fixture!("gitlab_merge_request.json"),
        fixture!("gitlab_draft_conflicting_merge_request.json"),
    ] {
        let stdout = fixture["stdout"].as_str().unwrap();
        let (forge, _) = gitlab(stdout);
        let number = fixture["expected"]["review"]["number"].as_i64().unwrap();
        let review = forge.review_by_number(number).await.unwrap().unwrap();
        assert_review(&review, &fixture["expected"]["review"]);
        let (forge, runner) = gitlab(stdout);
        assert_checks(&forge.checks(number).await, &fixture["expected"]["checks"]);
        let call = &runner.calls()[0];
        assert_eq!(call.program, "glab");
        assert!(call.args[1].ends_with(&format!("/merge_requests/{number}")));
    }
}

#[tokio::test]
async fn gitlab_discussions_match_the_desktop() {
    let fixture = fixture!("gitlab_discussions.json");
    let (forge, runner) = gitlab(fixture["stdout"].as_str().unwrap());
    let (comments, truncated) = forge.comments(42).await;
    assert!(!truncated);
    assert_comments(&comments, &fixture["expected"]["comments"]);
    let call = &runner.calls()[0];
    assert_eq!(call.option("output"), Some("ndjson"));
    assert!(call.args.contains(&"--paginate".to_string()));
    // A host with a port is addressed through GITLAB_REPO, not --hostname.
    assert!(!call.args.contains(&"--hostname".to_string()));
    assert_eq!(
        call.environment,
        vec![(
            "GITLAB_REPO".to_string(),
            "https://gitlab.acme.test:8443/platform/mobile/alera".to_string()
        )]
    );
}

#[tokio::test]
async fn azure_pull_requests_match_the_desktop() {
    let fixture = fixture!("azure_pull_requests.json");
    let (forge, runner) = azure(&fixture);
    let review = forge.review_for_branch("feature").await.unwrap().unwrap();
    assert_review(&review, &fixture["expected"]["review"]);
    let call = &runner.calls()[0];
    assert_eq!(call.program, "az");
    assert_eq!(call.args[..3], ["repos", "pr", "list"]);
    assert_eq!(
        call.option("organization"),
        Some("https://dev.azure.com/myorg")
    );
    assert_eq!(call.option("project"), Some("myproject"));
    assert_eq!(call.option("source-branch"), Some("feature"));
    assert_eq!(call.option("top"), Some("100"));

    let fixture = fixture!("azure_completed_pull_request.json");
    let (forge, _) = azure(&fixture);
    let review = forge.review_by_number(9).await.unwrap().unwrap();
    assert_review(&review, &fixture["expected"]["review"]);
}

#[tokio::test]
async fn azure_policies_and_threads_match_the_desktop() {
    let fixture = fixture!("azure_policies.json");
    let (forge, runner) = azure(&fixture);
    assert_checks(&forge.checks(42).await, &fixture["expected"]["checks"]);
    assert_eq!(
        runner.calls()[0].args[..4],
        ["repos", "pr", "policy", "list"]
    );

    let fixture = fixture!("azure_threads.json");
    let (forge, runner) = azure(&fixture);
    let (comments, truncated) = forge.comments(42).await;
    assert!(!truncated);
    assert_comments(&comments, &fixture["expected"]["comments"]);
    let call = &runner.calls()[0];
    assert_eq!(call.args[..2], ["devops", "invoke"]);
    assert_eq!(call.option("resource"), Some("pullRequestThreads"));
    assert_eq!(call.option("http-method"), Some("GET"));
}
