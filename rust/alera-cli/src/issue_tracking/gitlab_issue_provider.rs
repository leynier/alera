use serde_json::Value;

use super::forge_cli_failure::{nested_string, run_json, string_field, string_list, ForgeCli};
use super::IssueState;
use super::{ForgeCliRunner, IssueDetails, IssueFetchError, IssueProvider, IssueReference};

const GLAB: ForgeCli = ForgeCli {
    program: "glab",
    display: "The GitLab CLI (glab)",
    install_hint: "Install it from https://gitlab.com/gitlab-org/cli and run glab auth login.",
    auth_hint: "Run glab auth login for this GitLab host.",
};

pub(super) async fn fetch_gitlab_issue(
    reference: &IssueReference,
    runner: &dyn ForgeCliRunner,
) -> Result<IssueDetails, IssueFetchError> {
    let args = vec![
        "issue".to_string(),
        "view".to_string(),
        reference.url.clone(),
        "--output".to_string(),
        "json".to_string(),
    ];
    let value = run_json(runner, &GLAB, args).await?;
    Ok(map_gitlab_issue(reference, &value))
}

fn map_gitlab_issue(reference: &IssueReference, value: &Value) -> IssueDetails {
    let raw_state = string_field(value, "state").unwrap_or_default();
    let (state, state_label) = match raw_state.to_ascii_lowercase().as_str() {
        "opened" | "open" => (IssueState::Open, Some("Open".to_string())),
        "closed" => (IssueState::Closed, Some("Closed".to_string())),
        _ => (
            IssueState::Unknown,
            (!raw_state.is_empty()).then_some(raw_state),
        ),
    };
    IssueDetails {
        provider: IssueProvider::GitLab,
        // Keep the linked URL: GitLab now answers with `/-/work_items/N` even
        // for an `/-/issues/N` link, and both open the same page.
        url: reference.url.clone(),
        repository: reference.repository.clone(),
        number: value
            .get("iid")
            .and_then(Value::as_i64)
            .or(reference.number)
            .unwrap_or_default(),
        title: string_field(value, "title").unwrap_or_default(),
        state,
        state_label,
        body: string_field(value, "description"),
        labels: string_list(value, "labels", None),
        assignees: string_list(value, "assignees", Some("username")),
        author: nested_string(value, "author", "username"),
        created_at: string_field(value, "created_at"),
        updated_at: string_field(value, "updated_at"),
    }
}

#[cfg(test)]
mod tests {
    use super::super::forge_cli_failure::fake::FakeForgeCliRunner;
    use super::super::parse_issue_reference;
    use super::*;

    const SAMPLE: &str = r#"{"id":105226057,"iid":1,"state":"closed","description":"","author":{"username":"profclems"},"assignees":[{"username":"dev"}],"updated_at":"2024-07-24T21:14:34.463Z","title":"Add functionality to merge merge request","created_at":"2020-07-24T23:57:04Z","labels":["enhancement"],"web_url":"https://gitlab.com/gitlab-org/cli/-/work_items/1"}"#;

    #[tokio::test]
    async fn fetches_through_glab_issue_view() {
        let reference =
            parse_issue_reference("https://gitlab.com/gitlab-org/cli/-/issues/1").unwrap();
        let runner = FakeForgeCliRunner::replying(0, SAMPLE, "");
        let issue = fetch_gitlab_issue(&reference, &runner).await.unwrap();
        let (program, args) = runner.last_call();
        assert_eq!(program, "glab");
        assert_eq!(
            args,
            vec![
                "issue",
                "view",
                "https://gitlab.com/gitlab-org/cli/-/issues/1",
                "--output",
                "json"
            ]
        );
        assert_eq!(issue.number, 1);
        assert_eq!(issue.state, IssueState::Closed);
        assert_eq!(issue.body, None);
        assert_eq!(issue.labels, vec!["enhancement"]);
        assert_eq!(issue.assignees, vec!["dev"]);
        assert_eq!(issue.author.as_deref(), Some("profclems"));
        assert_eq!(issue.url, "https://gitlab.com/gitlab-org/cli/-/issues/1");
        assert_eq!(issue.repository.as_deref(), Some("gitlab-org/cli"));
    }

    #[tokio::test]
    async fn maps_gitlab_not_found() {
        let reference =
            parse_issue_reference("https://gitlab.com/gitlab-org/cli/-/issues/99999999").unwrap();
        let runner = FakeForgeCliRunner::replying(1, "", "\n   ERROR  \n\n  404 Not Found.\n");
        match fetch_gitlab_issue(&reference, &runner).await {
            Err(IssueFetchError::NotFound(message)) => assert_eq!(message, "404 Not Found."),
            other => panic!("unexpected {other:?}"),
        }
    }
}
