use serde_json::Value;

use super::forge_cli_failure::{run_json, string_field, ForgeCli};
use super::IssueState;
use super::{ForgeCliRunner, IssueDetails, IssueFetchError, IssueProvider, IssueReference};

const AZ_BOARDS: ForgeCli = ForgeCli {
    program: "az",
    display: "The Azure CLI with the azure-devops extension",
    install_hint: "Install the Azure CLI and run az extension add --name azure-devops.",
    auth_hint: "Run az login, or az devops login with a personal access token.",
};

/// Work item states Azure DevOps processes ship as done. States are
/// process-defined, so anything else counts as open and the raw value is kept.
const CLOSED_STATES: &[&str] = &["closed", "done", "removed", "resolved", "completed"];

pub(super) async fn fetch_azure_devops_work_item(
    reference: &IssueReference,
    runner: &dyn ForgeCliRunner,
) -> Result<IssueDetails, IssueFetchError> {
    let (Some(number), Some(organization)) = (reference.number, reference.azure_organization_url())
    else {
        return Err(IssueFetchError::Unsupported(format!(
            "Not an Azure DevOps work item URL: {}",
            reference.url
        )));
    };
    let args = vec![
        "boards".to_string(),
        "work-item".to_string(),
        "show".to_string(),
        "--id".to_string(),
        number.to_string(),
        "--org".to_string(),
        organization,
        "--expand".to_string(),
        "fields".to_string(),
        "--output".to_string(),
        "json".to_string(),
    ];
    let value = run_json(runner, &AZ_BOARDS, args).await?;
    Ok(map_work_item(reference, number, &value))
}

fn map_work_item(reference: &IssueReference, number: i64, value: &Value) -> IssueDetails {
    let fields = value.get("fields").cloned().unwrap_or(Value::Null);
    let raw_state = string_field(&fields, "System.State");
    let state = match raw_state.as_deref() {
        Some(state) if CLOSED_STATES.contains(&state.to_ascii_lowercase().as_str()) => {
            IssueState::Closed
        }
        Some(_) => IssueState::Open,
        None => IssueState::Unknown,
    };
    IssueDetails {
        provider: IssueProvider::AzureDevOps,
        url: reference.url.clone(),
        repository: reference.repository.clone(),
        number: value.get("id").and_then(Value::as_i64).unwrap_or(number),
        title: string_field(&fields, "System.Title").unwrap_or_default(),
        state,
        state_label: raw_state,
        body: string_field(&fields, "System.Description"),
        labels: string_field(&fields, "System.Tags")
            .map(|tags| {
                tags.split(';')
                    .map(str::trim)
                    .filter(|tag| !tag.is_empty())
                    .map(ToOwned::to_owned)
                    .collect()
            })
            .unwrap_or_default(),
        assignees: identity(&fields, "System.AssignedTo").into_iter().collect(),
        author: identity(&fields, "System.CreatedBy"),
        created_at: string_field(&fields, "System.CreatedDate"),
        updated_at: string_field(&fields, "System.ChangedDate"),
    }
}

/// Identity fields are objects in current API versions and plain
/// `Name <email>` strings in older ones.
fn identity(fields: &Value, key: &str) -> Option<String> {
    let value = fields.get(key)?;
    if let Some(text) = value.as_str() {
        return Some(text.to_string()).filter(|text| !text.trim().is_empty());
    }
    string_field(value, "uniqueName").or_else(|| string_field(value, "displayName"))
}

#[cfg(test)]
mod tests {
    use super::super::forge_cli_failure::fake::FakeForgeCliRunner;
    use super::super::parse_issue_reference;
    use super::*;

    const SAMPLE: &str = r#"{"id":42,"fields":{"System.Title":"Checkout fails","System.State":"Resolved","System.Description":"<div>Steps</div>","System.Tags":"bug; checkout","System.AssignedTo":{"displayName":"Dev","uniqueName":"dev@contoso.com"},"System.CreatedBy":"Lead <lead@contoso.com>","System.CreatedDate":"2026-01-01T00:00:00Z","System.ChangedDate":"2026-01-02T00:00:00Z"}}"#;

    #[tokio::test]
    async fn fetches_through_az_boards() {
        let reference =
            parse_issue_reference("https://dev.azure.com/contoso/Fabrikam/_workitems/edit/42")
                .unwrap();
        let runner = FakeForgeCliRunner::replying(0, SAMPLE, "");
        let issue = fetch_azure_devops_work_item(&reference, &runner)
            .await
            .unwrap();
        let (program, args) = runner.last_call();
        assert_eq!(program, "az");
        assert_eq!(
            args,
            vec![
                "boards",
                "work-item",
                "show",
                "--id",
                "42",
                "--org",
                "https://dev.azure.com/contoso",
                "--expand",
                "fields",
                "--output",
                "json"
            ]
        );
        assert_eq!(issue.title, "Checkout fails");
        assert_eq!(issue.state, IssueState::Closed);
        assert_eq!(issue.state_label.as_deref(), Some("Resolved"));
        assert_eq!(issue.labels, vec!["bug", "checkout"]);
        assert_eq!(issue.assignees, vec!["dev@contoso.com"]);
        assert_eq!(issue.author.as_deref(), Some("Lead <lead@contoso.com>"));
        assert_eq!(issue.body.as_deref(), Some("<div>Steps</div>"));
    }

    #[tokio::test]
    async fn reports_missing_extension_and_missing_work_item() {
        let reference =
            parse_issue_reference("https://dev.azure.com/contoso/Fabrikam/_workitems/edit/42")
                .unwrap();
        let no_extension = FakeForgeCliRunner::replying(
            2,
            "",
            "ERROR: 'boards' is misspelled or not recognized by the system.",
        );
        assert!(matches!(
            fetch_azure_devops_work_item(&reference, &no_extension).await,
            Err(IssueFetchError::CliMissing { .. })
        ));
        let missing_item = FakeForgeCliRunner::replying(
            1,
            "",
            "ERROR: TF401232: Work item 42 does not exist, or you do not have permissions to read it.",
        );
        assert!(matches!(
            fetch_azure_devops_work_item(&reference, &missing_item).await,
            Err(IssueFetchError::NotFound(_))
        ));
    }

    #[test]
    fn unrecognized_states_count_as_open() {
        let reference =
            parse_issue_reference("https://contoso.visualstudio.com/Fabrikam/_workitems/edit/5")
                .unwrap();
        let value: Value =
            serde_json::from_str(r#"{"fields":{"System.Title":"t","System.State":"Active"}}"#)
                .unwrap();
        let issue = map_work_item(&reference, 5, &value);
        assert_eq!(issue.state, IssueState::Open);
        assert_eq!(issue.number, 5);
        assert!(issue.assignees.is_empty());
    }
}
