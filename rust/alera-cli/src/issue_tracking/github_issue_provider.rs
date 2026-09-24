use serde_json::Value;

use super::forge_cli_failure::{nested_string, run_json, string_field, string_list, ForgeCli};
use super::IssueState;
use super::{ForgeCliRunner, IssueDetails, IssueFetchError, IssueProvider, IssueReference};

const GH: ForgeCli = ForgeCli {
    program: "gh",
    display: "The GitHub CLI (gh)",
    install_hint: "Install it from https://cli.github.com and run gh auth login.",
    auth_hint: "Run gh auth login.",
};

const GH_ISSUE_FIELDS: &str =
    "number,title,state,stateReason,body,labels,assignees,author,createdAt,updatedAt,url";

pub(super) async fn fetch_github_issue(
    reference: &IssueReference,
    runner: &dyn ForgeCliRunner,
) -> Result<IssueDetails, IssueFetchError> {
    let args = vec![
        "issue".to_string(),
        "view".to_string(),
        reference.url.clone(),
        "--json".to_string(),
        GH_ISSUE_FIELDS.to_string(),
    ];
    let value = run_json(runner, &GH, args).await?;
    Ok(map_github_issue(reference, &value))
}

fn map_github_issue(reference: &IssueReference, value: &Value) -> IssueDetails {
    let raw_state = string_field(value, "state").unwrap_or_default();
    let state = match raw_state.to_ascii_uppercase().as_str() {
        "OPEN" => IssueState::Open,
        "CLOSED" => IssueState::Closed,
        _ => IssueState::Unknown,
    };
    let state_label = match (state, string_field(value, "stateReason")) {
        (IssueState::Closed, Some(reason)) if reason.eq_ignore_ascii_case("NOT_PLANNED") => {
            Some("Closed as not planned".to_string())
        }
        (IssueState::Open, _) => Some("Open".to_string()),
        (IssueState::Closed, _) => Some("Closed".to_string()),
        (IssueState::Unknown, _) => (!raw_state.is_empty()).then_some(raw_state),
    };
    IssueDetails {
        provider: IssueProvider::GitHub,
        url: string_field(value, "url").unwrap_or_else(|| reference.url.clone()),
        repository: reference.repository.clone(),
        number: value
            .get("number")
            .and_then(Value::as_i64)
            .or(reference.number)
            .unwrap_or_default(),
        title: string_field(value, "title").unwrap_or_default(),
        state,
        state_label,
        body: string_field(value, "body"),
        labels: string_list(value, "labels", Some("name")),
        assignees: string_list(value, "assignees", Some("login")),
        author: nested_string(value, "author", "login"),
        created_at: string_field(value, "createdAt"),
        updated_at: string_field(value, "updatedAt"),
    }
}

#[cfg(test)]
mod tests {
    use super::super::forge_cli_failure::fake::FakeForgeCliRunner;
    use super::super::parse_issue_reference;
    use super::*;

    const SAMPLE: &str = r#"{"assignees":[{"login":"octocat"}],"author":{"login":"leynier"},"body":"Details","createdAt":"2026-09-12T19:54:22Z","labels":[{"name":"feature"}],"number":758,"state":"OPEN","stateReason":"","title":"feat: link an issue to a workspace","updatedAt":"2026-09-12T19:54:26Z","url":"https://github.com/leynier/alera/issues/758"}"#;

    #[tokio::test]
    async fn fetches_through_gh_issue_view() {
        let reference =
            parse_issue_reference("https://github.com/leynier/alera/issues/758").unwrap();
        let runner = FakeForgeCliRunner::replying(0, SAMPLE, "");
        let issue = fetch_github_issue(&reference, &runner).await.unwrap();
        let (program, args) = runner.last_call();
        assert_eq!(program, "gh");
        assert_eq!(
            args,
            vec![
                "issue",
                "view",
                "https://github.com/leynier/alera/issues/758",
                "--json",
                GH_ISSUE_FIELDS
            ]
        );
        assert_eq!(issue.number, 758);
        assert_eq!(issue.title, "feat: link an issue to a workspace");
        assert_eq!(issue.state, IssueState::Open);
        assert_eq!(issue.state_label.as_deref(), Some("Open"));
        assert_eq!(issue.repository.as_deref(), Some("leynier/alera"));
        assert_eq!(issue.labels, vec!["feature"]);
        assert_eq!(issue.assignees, vec!["octocat"]);
        assert_eq!(issue.author.as_deref(), Some("leynier"));
        assert_eq!(issue.body.as_deref(), Some("Details"));
    }

    #[tokio::test]
    async fn classifies_missing_issue_and_signed_out_cli() {
        let reference =
            parse_issue_reference("https://github.com/leynier/alera/issues/4015").unwrap();
        let not_found = FakeForgeCliRunner::replying(
            1,
            "",
            "GraphQL: Could not resolve to an issue or pull request with the number of 4015. (repository.issue)",
        );
        assert!(matches!(
            fetch_github_issue(&reference, &not_found).await,
            Err(IssueFetchError::NotFound(_))
        ));
        let signed_out = FakeForgeCliRunner::replying(
            4,
            "",
            "To get started with GitHub CLI, please run:  gh auth login",
        );
        assert!(matches!(
            fetch_github_issue(&reference, &signed_out).await,
            Err(IssueFetchError::NotAuthenticated { .. })
        ));
        let missing = FakeForgeCliRunner::default();
        missing.push(Err(std::io::Error::from(std::io::ErrorKind::NotFound)));
        assert!(matches!(
            fetch_github_issue(&reference, &missing).await,
            Err(IssueFetchError::CliMissing { .. })
        ));
    }

    #[test]
    fn maps_closed_not_planned() {
        let reference = parse_issue_reference("https://github.com/a/b/issues/1").unwrap();
        let value: Value = serde_json::from_str(
            r#"{"number":1,"title":"t","state":"CLOSED","stateReason":"NOT_PLANNED"}"#,
        )
        .unwrap();
        let issue = map_github_issue(&reference, &value);
        assert_eq!(issue.state, IssueState::Closed);
        assert_eq!(issue.state_label.as_deref(), Some("Closed as not planned"));
        assert_eq!(issue.url, "https://github.com/a/b/issues/1");
    }
}
