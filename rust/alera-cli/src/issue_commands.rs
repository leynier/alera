//! `alera issue show <url>`: reads an issue without touching any workspace.
//! Runs the forge CLI directly, so it works without a runtime host.

use serde_json::json;

use crate::cli::{IssueAction, IssueCommand};
use crate::issue_tracking::{fetch_issue_url, IssueDetails, IssueState, SystemForgeCliRunner};

pub async fn run(command: IssueCommand) -> i32 {
    let json_output = command.output.json;
    match command.action {
        IssueAction::Show(args) => match fetch_issue_url(&args.url, &SystemForgeCliRunner).await {
            Ok(issue) => {
                if json_output {
                    crate::print_value(&issue, true, "");
                } else {
                    println!("{}", issue_text(&issue));
                }
                0
            }
            Err(error) => {
                if json_output {
                    crate::print_value(&json!({ "error": error.to_json() }), true, "");
                }
                crate::print_error(error)
            }
        },
    }
}

/// Human-readable issue, shared with `alera workspace issue show`.
pub(crate) fn issue_text(issue: &IssueDetails) -> String {
    let mut lines = vec![
        format!(
            "#{} {} - {}",
            issue.number,
            state_text(issue.state, issue.state_label.as_deref()),
            issue.title
        ),
        issue.url.clone(),
    ];
    if !issue.labels.is_empty() {
        lines.push(format!("Labels: {}", issue.labels.join(", ")));
    }
    if !issue.assignees.is_empty() {
        lines.push(format!("Assignees: {}", issue.assignees.join(", ")));
    }
    if let Some(author) = &issue.author {
        lines.push(format!("Author: {author}"));
    }
    if let Some(body) = issue.body.as_deref().filter(|body| !body.trim().is_empty()) {
        lines.push(String::new());
        lines.push(body.trim_end().to_string());
    }
    lines.join("\n")
}

pub(crate) fn state_text(state: IssueState, label: Option<&str>) -> String {
    match label {
        Some(label) => label.to_string(),
        None => match state {
            IssueState::Open => "Open".to_string(),
            IssueState::Closed => "Closed".to_string(),
            IssueState::Unknown => "Unknown".to_string(),
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::issue_tracking::IssueProvider;

    #[test]
    fn formats_issue_details_for_terminals() {
        let issue = IssueDetails {
            provider: IssueProvider::GitHub,
            url: "https://github.com/leynier/alera/issues/758".into(),
            repository: Some("leynier/alera".into()),
            number: 758,
            title: "Link an issue".into(),
            state: IssueState::Open,
            state_label: None,
            body: Some("Details\n".into()),
            labels: vec!["feature".into()],
            assignees: vec![],
            author: Some("leynier".into()),
            created_at: None,
            updated_at: None,
        };
        assert_eq!(
            issue_text(&issue),
            "#758 Open - Link an issue\nhttps://github.com/leynier/alera/issues/758\nLabels: feature\nAuthor: leynier\n\nDetails"
        );
    }
}
