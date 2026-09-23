//! `alera workspace issue show|link|unlink`.
//!
//! Goes through a running host that advertises `linkedIssuesV1`, so the app
//! refreshes from its broadcast; otherwise edits the runtime store directly,
//! the same fallback the other workspace record commands use.

use alera_core::runtime::{LinkedIssue, RuntimeStore};
use anyhow::Result;
use serde_json::{json, Value};

use crate::cli::{
    RuntimeDirArgs, WorkspaceIssueAction, WorkspaceIssueCommand, WorkspaceIssueTargetArgs,
};
use crate::issue_commands::{issue_text, state_text};
use crate::issue_tracking::{IssueDetails, IssueState, SystemForgeCliRunner};
use crate::linked_issue_service::{link_workspace_issue, refresh_workspace_issue};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::RUNTIME_HOST_LINKED_ISSUES_CAPABILITY;
use crate::workspace_context::resolve_requested_workspace_id;

pub async fn run(
    runtime: RuntimeDirArgs,
    command: WorkspaceIssueCommand,
    json_output: bool,
) -> i32 {
    let target = match &command.action {
        WorkspaceIssueAction::Show(args) => &args.target,
        WorkspaceIssueAction::Link(args) => &args.target,
        WorkspaceIssueAction::Unlink(args) => args,
    };
    let workspace_id = match workspace_id(&runtime, target).await {
        Ok(Some(id)) => id,
        Ok(None) => {
            eprintln!(
                "--workspace-id is required (or run inside an Alera terminal where ALERA_WORKSPACE_ID is set)."
            );
            return crate::USAGE_EXIT_CODE;
        }
        Err(error) => return crate::print_error(error),
    };
    let result = match command.action {
        WorkspaceIssueAction::Show(args) => {
            show(&runtime, &workspace_id, args.cached, json_output).await
        }
        WorkspaceIssueAction::Link(args) => {
            link(&runtime, &workspace_id, &args.url, json_output).await
        }
        WorkspaceIssueAction::Unlink(_) => unlink(&runtime, &workspace_id, json_output).await,
    };
    result.unwrap_or_else(crate::print_error)
}

async fn workspace_id(
    runtime: &RuntimeDirArgs,
    target: &WorkspaceIssueTargetArgs,
) -> Result<Option<String>> {
    resolve_requested_workspace_id(runtime, target.workspace_id.as_deref()).await
}

enum Backend {
    Host(RuntimeHostRpcClient),
    Store(RuntimeStore),
}

async fn backend(runtime: &RuntimeDirArgs) -> Result<Backend> {
    let dir = crate::runtime_dir(runtime);
    if let Some(client) = RuntimeHostRpcClient::connect_with_required_capability(
        &dir,
        RUNTIME_HOST_LINKED_ISSUES_CAPABILITY,
    )
    .await?
    {
        return Ok(Backend::Host(client));
    }
    Ok(Backend::Store(RuntimeStore::open(&dir).await?))
}

async fn show(
    runtime: &RuntimeDirArgs,
    workspace_id: &str,
    cached: bool,
    json_output: bool,
) -> Result<i32> {
    let outcome = match (backend(runtime).await?, cached) {
        (Backend::Host(mut client), true) => {
            let record = client
                .request_value("linkedIssue.find", &json!({ "workspaceId": workspace_id }))
                .await?;
            json!({ "linkedIssue": record, "issue": null, "fetchError": null })
        }
        (Backend::Store(store), true) => {
            let record = store.find_linked_issue(workspace_id).await?;
            json!({ "linkedIssue": record, "issue": null, "fetchError": null })
        }
        (Backend::Host(mut client), false) => {
            let record = client
                .request_value("linkedIssue.find", &json!({ "workspaceId": workspace_id }))
                .await?;
            if record.is_null() {
                return Ok(report_missing(workspace_id, json_output));
            }
            client
                .request_value(
                    "linkedIssue.refresh",
                    &json!({ "workspaceId": workspace_id }),
                )
                .await?
        }
        (Backend::Store(store), false) => {
            if store.find_linked_issue(workspace_id).await?.is_none() {
                return Ok(report_missing(workspace_id, json_output));
            }
            refresh_workspace_issue(&store, workspace_id, &SystemForgeCliRunner)
                .await?
                .to_json()
        }
    };
    if outcome["linkedIssue"].is_null() {
        return Ok(report_missing(workspace_id, json_output));
    }
    if json_output {
        crate::print_value(&outcome, true, "");
        return Ok(0);
    }
    warn_fetch_error(&outcome);
    match serde_json::from_value::<IssueDetails>(outcome["issue"].clone()) {
        Ok(issue) => println!("{}", issue_text(&issue)),
        Err(_) => println!(
            "{}",
            cached_text(&serde_json::from_value(outcome["linkedIssue"].clone())?)
        ),
    }
    Ok(0)
}

async fn link(
    runtime: &RuntimeDirArgs,
    workspace_id: &str,
    url: &str,
    json_output: bool,
) -> Result<i32> {
    let outcome = match backend(runtime).await? {
        Backend::Host(mut client) => {
            client
                .request_value(
                    "linkedIssue.link",
                    &json!({ "workspaceId": workspace_id, "url": url }),
                )
                .await?
        }
        Backend::Store(store) => {
            link_workspace_issue(&store, workspace_id, url, &SystemForgeCliRunner, |_| {})
                .await?
                .to_json()
        }
    };
    if json_output {
        crate::print_value(&outcome, true, "");
        return Ok(0);
    }
    warn_fetch_error(&outcome);
    let record: LinkedIssue = serde_json::from_value(outcome["linkedIssue"].clone())?;
    println!("Linked {}", cached_text(&record));
    Ok(0)
}

async fn unlink(runtime: &RuntimeDirArgs, workspace_id: &str, json_output: bool) -> Result<i32> {
    let removed = match backend(runtime).await? {
        Backend::Host(mut client) => client
            .request_value(
                "linkedIssue.remove",
                &json!({ "workspaceId": workspace_id }),
            )
            .await?["removed"]
            .as_bool()
            .unwrap_or(false),
        Backend::Store(store) => store.remove_linked_issue(workspace_id).await?,
    };
    let message = if removed {
        format!("Unlinked the issue from workspace {workspace_id}")
    } else {
        format!("Workspace {workspace_id} had no linked issue")
    };
    crate::print_value(
        &json!({ "workspaceId": workspace_id, "removed": removed }),
        json_output,
        &message,
    );
    Ok(0)
}

fn report_missing(workspace_id: &str, json_output: bool) -> i32 {
    if json_output {
        crate::print_value(&json!({ "linkedIssue": null }), true, "");
    }
    eprintln!("Workspace {workspace_id} has no linked issue");
    1
}

/// A failed fetch never fails the command: the link is stored either way.
fn warn_fetch_error(outcome: &Value) {
    if let Some(message) = outcome["fetchError"]["message"].as_str() {
        eprintln!("warning: could not fetch the issue: {message}");
    }
}

fn cached_text(record: &LinkedIssue) -> String {
    let heading = match (record.number, record.title.as_deref()) {
        (Some(number), Some(title)) => {
            let state = match record.state.as_deref() {
                Some("open") => IssueState::Open,
                Some("closed") => IssueState::Closed,
                _ => IssueState::Unknown,
            };
            Some(format!(
                "#{number} {} - {title}",
                state_text(state, record.state_label.as_deref())
            ))
        }
        (Some(number), None) => Some(format!("#{number}")),
        _ => None,
    };
    match heading {
        Some(heading) => format!("{heading}\n{}", record.url),
        None => record.url.clone(),
    }
}
