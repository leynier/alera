use super::*;

fn parse(url: &str) -> IssueReference {
    parse_issue_reference(url).expect("valid url")
}

#[test]
fn recognizes_github_issue_urls() {
    let reference = parse("  https://github.com/leynier/alera/issues/758  ");
    assert_eq!(reference.url, "https://github.com/leynier/alera/issues/758");
    assert_eq!(reference.provider, Some(IssueProvider::GitHub));
    assert_eq!(reference.repository.as_deref(), Some("leynier/alera"));
    assert_eq!(reference.number, Some(758));
    let with_anchor = parse("https://github.com/leynier/alera/issues/758#issuecomment-1");
    assert_eq!(with_anchor.number, Some(758));
}

#[test]
fn github_pull_request_urls_are_not_issues() {
    let reference = parse("https://github.com/leynier/alera/pull/758");
    assert_eq!(reference.provider, None);
    assert_eq!(reference.number, None);
}

#[test]
fn recognizes_gitlab_issue_and_work_item_urls_with_subgroups() {
    let issue = parse("https://gitlab.com/group/sub/project/-/issues/12");
    assert_eq!(issue.provider, Some(IssueProvider::GitLab));
    assert_eq!(issue.repository.as_deref(), Some("group/sub/project"));
    assert_eq!(issue.number, Some(12));
    let work_item = parse("https://gitlab.com/gitlab-org/cli/-/work_items/1");
    assert_eq!(work_item.provider, Some(IssueProvider::GitLab));
    assert_eq!(work_item.repository.as_deref(), Some("gitlab-org/cli"));
    let self_hosted = parse("https://git.example.com:8443/team/app/-/issues/3");
    assert_eq!(self_hosted.provider, Some(IssueProvider::GitLab));
    assert_eq!(self_hosted.host, "git.example.com:8443");
    let legacy = parse("https://gitlab.com/group/project/issues/4");
    assert_eq!(legacy.provider, Some(IssueProvider::GitLab));
}

#[test]
fn recognizes_azure_devops_work_items() {
    let modern = parse("https://dev.azure.com/contoso/Fabrikam/_workitems/edit/42");
    assert_eq!(modern.provider, Some(IssueProvider::AzureDevOps));
    assert_eq!(modern.repository.as_deref(), Some("contoso/Fabrikam"));
    assert_eq!(modern.number, Some(42));
    assert_eq!(
        modern.azure_organization_url().as_deref(),
        Some("https://dev.azure.com/contoso")
    );
    let legacy = parse("https://contoso.visualstudio.com/Fabrikam/_workitems/edit/7");
    assert_eq!(legacy.repository.as_deref(), Some("contoso/Fabrikam"));
    assert_eq!(
        legacy.azure_organization_url().as_deref(),
        Some("https://contoso.visualstudio.com")
    );
    let collection =
        parse("https://contoso.visualstudio.com/DefaultCollection/Fabrikam/_workitems/edit/7");
    assert_eq!(collection.repository.as_deref(), Some("contoso/Fabrikam"));
}

#[test]
fn unrecognized_trackers_keep_only_the_url() {
    let reference = parse("https://example.atlassian.net/browse/ABC-123");
    assert_eq!(reference.provider, None);
    assert_eq!(reference.repository, None);
    assert_eq!(reference.number, None);
    assert_eq!(reference.host, "example.atlassian.net");
    let enterprise = parse("https://github.example.com/org/repo/issues/9");
    assert_eq!(enterprise.provider, None);
    assert_eq!(enterprise.azure_organization_url(), None);
}

#[test]
fn rejects_non_http_urls() {
    assert!(matches!(
        parse_issue_reference("not a url"),
        Err(IssueFetchError::InvalidUrl(_))
    ));
    assert!(matches!(
        parse_issue_reference("ftp://github.com/a/b/issues/1"),
        Err(IssueFetchError::InvalidUrl(_))
    ));
    assert!(parse("https://github.com/a/b/issues/0").number.is_none());
}
