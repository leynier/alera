//! Write commands and failure classification of every provider against a
//! fake runner: no forge CLI or network is touched.

use std::sync::Arc;

use super::super::mobile_pull_request_identity::GitHubIdentity;
use super::azure::AzureDevOpsForge;
use super::github::GitHubForge;
use super::gitlab::{merge_request_number, GitLabForge};
use super::identity::{resolve_identity, ForgeIdentity, ForgeKind};
use super::model::MergeMethod;
use super::provider::{AuthStatus, CommentLocator, CommentSource, CreateInput, ForgeProvider};
use super::runner::fake::{failed, ok, FakeRunner};
use super::runner::ForgeOutput;

fn gitlab(outputs: Vec<ForgeOutput>) -> (GitLabForge, Arc<FakeRunner>) {
    let runner = Arc::new(FakeRunner::new(outputs));
    let identity = resolve_identity("git@gitlab.com:group/sub/app.git", None).unwrap();
    (
        GitLabForge {
            identity,
            runner: runner.clone(),
        },
        runner,
    )
}

fn azure(outputs: Vec<ForgeOutput>) -> (AzureDevOpsForge, Arc<FakeRunner>) {
    let runner = Arc::new(FakeRunner::new(outputs));
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

fn input(draft: bool) -> CreateInput {
    CreateInput {
        base: "main".into(),
        head: "feat/x".into(),
        title: "Add X".into(),
        body: "Why".into(),
        draft,
    }
}

fn error_code(error: crate::terminal_host::host_error::HostError) -> String {
    error.wire_response(1)["errorCode"]
        .as_str()
        .unwrap_or("")
        .to_string()
}

#[tokio::test]
async fn gitlab_writes_run_the_desktop_glab_commands() {
    let (forge, runner) = gitlab(vec![
        ok("https://gitlab.com/group/sub/app/-/merge_requests/12\n"),
        ok(""),
        ok(""),
        ok(""),
        ok("{}"),
        ok("{}"),
    ]);
    let created = forge.create(&input(true)).await.unwrap();
    assert_eq!(created.number, 12);
    forge
        .merge(12, MergeMethod::Squash, Some("abc"))
        .await
        .unwrap();
    forge.set_draft(12, false).await.unwrap();
    forge.close(12).await.unwrap();
    forge.comment(12, "Ready", None).await.unwrap();
    let reply = CommentLocator {
        source: CommentSource::ReviewThread,
        comment_id: 5,
        thread_id: Some("d1".into()),
    };
    forge
        .update_comment(12, &reply, "- [x] done")
        .await
        .unwrap();
    let calls = runner.calls();
    let repo = "https://gitlab.com/group/sub/app";
    assert_eq!(
        calls[0].args,
        [
            "mr",
            "create",
            "--repo",
            repo,
            "--source-branch",
            "feat/x",
            "--target-branch",
            "main",
            "--title",
            "Add X",
            "--description",
            "Why",
            "--draft",
            "--yes"
        ]
    );
    assert_eq!(
        calls[1].args,
        [
            "mr",
            "merge",
            "12",
            "--repo",
            repo,
            "--squash",
            "--sha",
            "abc",
            "--auto-merge=false",
            "--yes"
        ]
    );
    assert_eq!(
        calls[2].args,
        ["mr", "update", "12", "--repo", repo, "--ready", "--yes"]
    );
    assert_eq!(calls[3].args, ["mr", "close", "12", "--repo", repo]);
    assert_eq!(
        calls[4].args[1],
        "projects/group%2Fsub%2Fapp/merge_requests/12/notes"
    );
    assert_eq!(calls[4].option("method"), Some("POST"));
    assert_eq!(calls[4].option("raw-field"), Some("body=Ready"));
    assert_eq!(calls[4].option("hostname"), Some("gitlab.com"));
    assert_eq!(
        calls[5].args[1],
        "projects/group%2Fsub%2Fapp/merge_requests/12/discussions/d1/notes/5"
    );
    assert_eq!(calls[5].option("method"), Some("PUT"));
    assert!(forge.merge(12, MergeMethod::Rebase, None).await.is_err());
}

#[tokio::test]
async fn azure_writes_run_the_desktop_az_commands() {
    let created = r#"{"pullRequestId":43,"title":"Add X","status":"active"}"#;
    let (forge, runner) = azure(vec![
        ok(created),
        ok(r#"{"pullRequestId":43,"lastMergeSourceCommit":{"commitId":"abc"}}"#),
        ok(""),
        ok(""),
        ok(""),
        ok("{}"),
    ]);
    let created = forge.create(&input(true)).await.unwrap();
    assert_eq!(created.number, 43);
    assert_eq!(
        created.url.as_deref(),
        Some("https://dev.azure.com/myorg/myproject/_git/myrepo/pullrequest/43")
    );
    forge
        .merge(43, MergeMethod::MergeCommit, Some("abc"))
        .await
        .unwrap();
    forge.set_draft(43, true).await.unwrap();
    forge.close(43).await.unwrap();
    forge.comment(43, "Looks good", None).await.unwrap();
    let calls = runner.calls();
    assert_eq!(calls[0].args[..3], ["repos", "pr", "create"]);
    assert_eq!(calls[0].option("draft"), Some("true"));
    assert_eq!(calls[0].option("source-branch"), Some("feat/x"));
    assert_eq!(calls[1].args[..3], ["repos", "pr", "show"]);
    assert_eq!(calls[2].option("status"), Some("completed"));
    assert_eq!(calls[2].option("squash"), Some("false"));
    assert_eq!(calls[3].option("draft"), Some("true"));
    assert_eq!(calls[4].option("status"), Some("abandoned"));
    assert_eq!(calls[5].option("resource"), Some("pullRequestThreads"));
    assert_eq!(calls[5].option("http-method"), Some("POST"));
    let body_file = calls[5].option("in-file").unwrap();
    assert!(
        !std::path::Path::new(body_file).exists(),
        "the body file is removed"
    );
    assert!(forge.merge(43, MergeMethod::Rebase, None).await.is_err());
}

#[tokio::test]
async fn azure_refuses_to_merge_a_moved_head() {
    let (forge, runner) = azure(vec![ok(
        r#"{"pullRequestId":43,"lastMergeSourceCommit":{"commitId":"new"}}"#,
    )]);
    let error = forge
        .merge(43, MergeMethod::Squash, Some("old"))
        .await
        .unwrap_err();
    assert!(error.wire_message().contains("head changed"));
    assert_eq!(runner.calls().len(), 1, "nothing was completed");
}

#[tokio::test]
async fn missing_or_signed_out_clis_are_provider_unavailable() {
    let (forge, _) = gitlab(vec![failed(127, "glab: command not found")]);
    let error = forge.close(1).await.unwrap_err();
    assert!(error.wire_message().contains("(glab)"));
    assert_eq!(error_code(error), "provider_unavailable");
    let (forge, _) = gitlab(vec![failed(1, "401 Unauthorized")]);
    let error = forge.close(1).await.unwrap_err();
    assert!(error.wire_message().contains("glab auth login"));
    let (forge, _) = azure(vec![failed(1, "Please run 'az login' to setup account.")]);
    let error = forge.close(1).await.unwrap_err();
    assert!(error.wire_message().contains("az login"));
    assert_eq!(error_code(error), "provider_unavailable");
    let (forge, _) = azure(vec![failed(2, "'repos' is misspelled or not recognized")]);
    assert!(forge
        .close(1)
        .await
        .unwrap_err()
        .wire_message()
        .contains("azure-devops extension"));
    let (forge, _) = azure(vec![failed(1, "TF401180: not found")]);
    assert!(forge.review_by_number(1).await.unwrap().is_none());
    let (forge, _) = gitlab(vec![failed(127, "")]);
    assert_eq!(forge.auth_status().await.unwrap(), AuthStatus::CliMissing);
    let (forge, _) = azure(vec![failed(1, "Please run 'az login'")]);
    assert_eq!(
        forge.auth_status().await.unwrap(),
        AuthStatus::NotAuthenticated
    );
}

#[tokio::test]
async fn github_merges_bind_the_evaluated_head() {
    let runner = Arc::new(FakeRunner::new([ok(""), failed(127, "")]));
    let forge = GitHubForge {
        identity: resolve_identity("https://github.com/leynier/alera", None).unwrap(),
        github: GitHubIdentity {
            host: "github.com".into(),
            owner: "leynier".into(),
            repo: "alera".into(),
            slug: "leynier/alera".into(),
        },
        repo_path: "/repo".into(),
        runner: runner.clone(),
    };
    forge
        .merge(7, MergeMethod::Rebase, Some("abc"))
        .await
        .unwrap();
    assert_eq!(
        runner.calls()[0].args,
        [
            "pr",
            "merge",
            "7",
            "--repo",
            "leynier/alera",
            "--rebase",
            "--match-head-commit",
            "abc"
        ]
    );
    assert_eq!(error_code(forge.close(7).await.unwrap_err()), "ghMissing");
    assert!(forge
        .merge(7, MergeMethod::ProviderDefault, None)
        .await
        .is_err());
}

#[test]
fn review_references_must_name_this_repository() {
    let (gitlab, _) = gitlab(Vec::new());
    assert_eq!(gitlab.review_reference("#3").unwrap(), 3);
    assert_eq!(
        gitlab
            .review_reference("https://gitlab.com/group/sub/app/-/merge_requests/3/diffs")
            .unwrap(),
        3
    );
    for foreign in [
        "https://gitlab.com/group/other/-/merge_requests/3",
        "https://example.com/group/sub/app/-/merge_requests/3",
        "https://gitlab.com/group/sub/app/-/issues/3",
    ] {
        assert!(gitlab.review_reference(foreign).is_err(), "{foreign}");
    }
    let (azure, _) = azure(Vec::new());
    assert_eq!(
        azure
            .review_reference("https://dev.azure.com/myorg/myproject/_git/myrepo/pullrequest/43")
            .unwrap(),
        43
    );
    for foreign in [
        "https://dev.azure.com/other/myproject/_git/myrepo/pullrequest/43",
        "https://dev.azure.com/myorg/myproject/_git/other/pullrequest/43",
        "https://dev.azure.com/myorg/myproject/_git/myrepo/commit/43",
    ] {
        assert!(azure.review_reference(foreign).is_err(), "{foreign}");
    }
    assert_eq!(
        merge_request_number("Creating...\nhttps://h/g/p/-/merge_requests/9\n"),
        Some((9, "https://h/g/p/-/merge_requests/9".to_string()))
    );
    let identity: ForgeIdentity = resolve_identity("git@gitlab.com:g/p.git", None).unwrap();
    assert_eq!(identity.kind, ForgeKind::GitLab);
}
