//! Free text never reaches a forge CLI's command line, azure-cli never sees
//! an `@file` argument, and request body files never outlive their call.

use std::sync::Arc;

use super::azure::AzureDevOpsForge;
use super::gitlab::GitLabForge;
use super::identity::resolve_identity;
use super::model::MergeMethod;
use super::provider::{CommentLocator, CommentSource, CreateInput, ForgeProvider};
use super::runner::fake::{ok, FakeRunner};
use super::runner::ForgeOutput;

const HOSTILE_TITLE: &str = "Fix \" & calc & %PATH% $(id) `id` | more";
const HOSTILE_BODY: &str = "@/etc/passwd\r\n^& del /q *";
const HOSTILE_COMMENT: &str = "\"&calc&\" %USERPROFILE%";

fn hostile_input() -> CreateInput {
    CreateInput {
        base: "main&calc".into(),
        head: "feat/%PATH%|x".into(),
        title: HOSTILE_TITLE.into(),
        body: HOSTILE_BODY.into(),
        draft: false,
    }
}

fn reply() -> CommentLocator {
    CommentLocator {
        source: CommentSource::ReviewThread,
        comment_id: 5,
        thread_id: Some("7".into()),
    }
}

fn assert_no_free_text(runner: &FakeRunner) {
    let input = hostile_input();
    let free_text = [
        HOSTILE_TITLE,
        HOSTILE_BODY,
        HOSTILE_COMMENT,
        &input.head,
        &input.base,
    ];
    for call in runner.calls() {
        for arg in &call.args {
            for text in free_text {
                assert!(
                    !arg.contains(text),
                    "{text:?} reached argv: {:?}",
                    call.args
                );
            }
        }
    }
}

fn gitlab(outputs: Vec<ForgeOutput>) -> (GitLabForge, Arc<FakeRunner>) {
    let runner = Arc::new(FakeRunner::new(outputs));
    let identity = resolve_identity("git@gitlab.com:group/app.git", None).unwrap();
    (
        GitLabForge {
            identity,
            runner: runner.clone(),
        },
        runner,
    )
}

fn azure(runner: FakeRunner) -> (AzureDevOpsForge, Arc<FakeRunner>) {
    let runner = Arc::new(runner);
    let identity =
        resolve_identity("https://dev.azure.com/myorg/myproject/_git/myrepo", None).unwrap();
    (
        AzureDevOpsForge {
            identity,
            runner: runner.clone(),
        },
        runner,
    )
}

#[tokio::test]
async fn gitlab_free_text_travels_on_stdin_only() {
    let (forge, runner) = gitlab(vec![ok(r#"{"iid":3}"#), ok("{}"), ok("{}"), ok("{}")]);
    let created = forge.create(&hostile_input()).await.unwrap();
    assert_eq!(created.number, 3);
    forge.comment(3, HOSTILE_COMMENT, None).await.unwrap();
    forge
        .comment(3, HOSTILE_COMMENT, Some(&reply()))
        .await
        .unwrap();
    forge
        .update_comment(3, &reply(), HOSTILE_COMMENT)
        .await
        .unwrap();
    assert_no_free_text(&runner);
    let calls = runner.calls();
    let create: serde_json::Value =
        serde_json::from_str(calls[0].stdin.as_deref().unwrap()).unwrap();
    assert_eq!(create["title"], HOSTILE_TITLE);
    assert_eq!(create["description"], HOSTILE_BODY);
    assert_eq!(create["source_branch"], "feat/%PATH%|x");
    for call in &calls[1..] {
        let body: serde_json::Value = serde_json::from_str(call.stdin.as_deref().unwrap()).unwrap();
        assert_eq!(body["body"], HOSTILE_COMMENT);
        assert_eq!(call.option("input"), Some("-"));
    }
}

#[tokio::test]
async fn azure_free_text_travels_in_removed_body_files() {
    let created = r#"{"pullRequestId":43,"status":"active"}"#;
    let (forge, runner) = azure(FakeRunner::new([ok(created), ok("{}"), ok("{}"), ok("{}")]));
    assert_eq!(forge.create(&hostile_input()).await.unwrap().number, 43);
    forge.comment(43, HOSTILE_COMMENT, None).await.unwrap();
    forge
        .comment(43, HOSTILE_COMMENT, Some(&reply()))
        .await
        .unwrap();
    forge
        .update_comment(43, &reply(), HOSTILE_COMMENT)
        .await
        .unwrap();
    assert_no_free_text(&runner);
    let calls = runner.calls();
    for (index, call) in calls.iter().enumerate() {
        assert_eq!(call.args[..2], ["devops", "invoke"]);
        let path = call.option("in-file").unwrap();
        assert!(
            !std::path::Path::new(path).exists(),
            "call {index} left {path}"
        );
        assert!(runner.in_file(index).is_some(), "call {index} had a body");
    }
    let create: serde_json::Value = serde_json::from_str(&runner.in_file(0).unwrap()).unwrap();
    assert_eq!(create["title"], HOSTILE_TITLE);
    assert_eq!(create["description"], HOSTILE_BODY);
    assert_eq!(create["sourceRefName"], "refs/heads/feat/%PATH%|x");
    assert!(runner.in_file(3).unwrap().contains("USERPROFILE"));
}

#[tokio::test]
async fn azure_never_passes_an_at_argument() {
    let (forge, runner) = azure(FakeRunner::new([ok("[]")]));
    assert!(forge.review_for_branch("@secrets").await.unwrap().is_none());
    assert_eq!(
        runner.calls()[0].option("source-branch"),
        Some("refs/heads/@secrets")
    );

    let (mut forge, runner) = azure(FakeRunner::new([ok("[]")]));
    forge.identity.project = Some("@/etc/passwd".into());
    let error = forge.review_for_branch("main").await.unwrap_err();
    assert!(error
        .wire_message()
        .contains("azure-cli would read it as a file"));
    assert!(runner.calls().is_empty(), "az never ran");
}

#[tokio::test]
async fn azure_merge_binds_the_head_on_the_server() {
    let current = r#"{"pullRequestId":43,"lastMergeSourceCommit":{"commitId":"abc"},
        "completionOptions":{"deleteSourceBranch":true}}"#;
    let (forge, runner) = azure(FakeRunner::new([ok(current), ok("{}")]));
    forge
        .merge(43, MergeMethod::Squash, Some("abc"))
        .await
        .unwrap();
    let calls = runner.calls();
    assert_eq!(calls.len(), 2);
    assert_eq!(calls[1].option("http-method"), Some("PATCH"));
    assert!(!std::path::Path::new(calls[1].option("in-file").unwrap()).exists());
    let body: serde_json::Value = serde_json::from_str(&runner.in_file(1).unwrap()).unwrap();
    assert_eq!(body["lastMergeSourceCommit"]["commitId"], "abc");
    assert_eq!(body["status"], "completed");
    assert_eq!(body["completionOptions"]["deleteSourceBranch"], true);
    assert_eq!(body["completionOptions"]["mergeStrategy"], "squash");
}

#[tokio::test]
async fn a_remote_checkout_never_gets_a_local_body_file() {
    let current = r#"{"pullRequestId":43,"lastMergeSourceCommit":{"commitId":"abc"}}"#;
    let (forge, runner) = azure(FakeRunner::remote([ok(current), ok("")]));
    forge
        .merge(43, MergeMethod::Squash, Some("abc"))
        .await
        .unwrap();
    let calls = runner.calls();
    assert_eq!(calls[1].args[..3], ["repos", "pr", "update"]);
    assert_eq!(calls[1].option("status"), Some("completed"));
    assert!(calls.iter().all(|call| call.option("in-file").is_none()));

    let (forge, runner) = azure(FakeRunner::remote([]));
    assert!(forge.comment(43, "hi", None).await.is_err());
    assert!(runner.calls().is_empty());
}
