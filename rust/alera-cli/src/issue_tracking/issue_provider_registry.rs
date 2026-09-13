use super::azure_devops_issue_provider::fetch_azure_devops_work_item;
use super::github_issue_provider::fetch_github_issue;
use super::gitlab_issue_provider::fetch_gitlab_issue;
use super::{
    parse_issue_reference, ForgeCliRunner, IssueDetails, IssueFetchError, IssueProvider,
    IssueReference,
};

/// Dispatches a parsed reference to the adapter for its forge. Adding a
/// provider means adding a variant to [IssueProvider] and an arm here.
pub async fn fetch_issue(
    reference: &IssueReference,
    runner: &dyn ForgeCliRunner,
) -> Result<IssueDetails, IssueFetchError> {
    match reference.provider {
        Some(IssueProvider::GitHub) => fetch_github_issue(reference, runner).await,
        Some(IssueProvider::GitLab) => fetch_gitlab_issue(reference, runner).await,
        Some(IssueProvider::AzureDevOps) => fetch_azure_devops_work_item(reference, runner).await,
        None => Err(IssueFetchError::Unsupported(format!(
            "No issue provider recognizes {}. The link still opens in the browser.",
            reference.url
        ))),
    }
}

pub async fn fetch_issue_url(
    url: &str,
    runner: &dyn ForgeCliRunner,
) -> Result<IssueDetails, IssueFetchError> {
    let reference = parse_issue_reference(url)?;
    fetch_issue(&reference, runner).await
}

#[cfg(test)]
mod tests {
    use super::super::forge_cli_failure::fake::FakeForgeCliRunner;
    use super::*;

    #[tokio::test]
    async fn unrecognized_urls_are_unsupported_without_spawning() {
        let runner = FakeForgeCliRunner::default();
        let result = fetch_issue_url("https://linear.app/team/issue/ENG-1", &runner).await;
        assert!(matches!(result, Err(IssueFetchError::Unsupported(_))));
        assert!(runner.calls.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn dispatches_by_provider() {
        let runner =
            FakeForgeCliRunner::replying(0, r#"{"iid":3,"title":"t","state":"opened"}"#, "");
        let issue = fetch_issue_url("https://gitlab.com/a/b/-/issues/3", &runner)
            .await
            .unwrap();
        assert_eq!(issue.provider, IssueProvider::GitLab);
        assert_eq!(runner.last_call().0, "glab");
    }
}
