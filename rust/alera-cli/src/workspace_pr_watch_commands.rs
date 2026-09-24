//! `alera workspace pr-watch show|start|stop`.
//!
//! Goes through a running host that advertises `pullRequestWatchV1` so desktop
//! and mobile refresh from the broadcast; otherwise edits the runtime store
//! directly, the same fallback the other workspace record commands use.

use alera_core::runtime::{PullRequestWatch, RuntimeStore, WorkspaceStatus};
use anyhow::{anyhow, bail, Result};
use serde_json::{json, Value};

use crate::cli::{
    RuntimeDirArgs, WorkspacePrWatchAction, WorkspacePrWatchCommand, WorkspacePrWatchStartArgs,
    WorkspacePrWatchTargetArgs,
};
use crate::orchestration_commands::terminal_handle_env;
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::RUNTIME_HOST_PULL_REQUEST_WATCH_CAPABILITY;
use crate::workspace_context::resolve_requested_workspace_id;

pub async fn run(
    runtime: RuntimeDirArgs,
    command: WorkspacePrWatchCommand,
    json_output: bool,
) -> i32 {
    let target = match &command.action {
        WorkspacePrWatchAction::Show(args) | WorkspacePrWatchAction::Stop(args) => args,
        WorkspacePrWatchAction::Start(args) => &args.target,
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
        WorkspacePrWatchAction::Show(_) => show(&runtime, &workspace_id, json_output).await,
        WorkspacePrWatchAction::Start(args) => {
            start(&runtime, &workspace_id, args, json_output).await
        }
        WorkspacePrWatchAction::Stop(_) => stop(&runtime, &workspace_id, json_output).await,
    };
    result.unwrap_or_else(crate::print_error)
}

async fn workspace_id(
    runtime: &RuntimeDirArgs,
    target: &WorkspacePrWatchTargetArgs,
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
        RUNTIME_HOST_PULL_REQUEST_WATCH_CAPABILITY,
    )
    .await?
    {
        return Ok(Backend::Host(client));
    }
    Ok(Backend::Store(RuntimeStore::open(&dir).await?))
}

async fn show(runtime: &RuntimeDirArgs, workspace_id: &str, json_output: bool) -> Result<i32> {
    let watch = match backend(runtime).await? {
        Backend::Host(mut client) => {
            client
                .request_value(
                    "pullRequestWatch.find",
                    &json!({ "workspaceId": workspace_id }),
                )
                .await?
        }
        Backend::Store(store) => match store.find_pull_request_watch(workspace_id).await? {
            Some(watch) => serde_json::to_value(watch)?,
            None => Value::Null,
        },
    };
    if watch.is_null() {
        if json_output {
            crate::print_value(&json!({ "watch": null }), true, "");
        } else {
            println!("not watching");
        }
        return Ok(0);
    }
    crate::print_value(&watch, json_output, &watch_text(&watch));
    Ok(0)
}

async fn start(
    runtime: &RuntimeDirArgs,
    workspace_id: &str,
    args: WorkspacePrWatchStartArgs,
    json_output: bool,
) -> Result<i32> {
    if args.no_checks && args.no_comments && args.no_conflicts {
        bail!("Choose at least one of checks, comments, or conflicts.");
    }
    let handle = args
        .handle
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string)
        .or_else(terminal_handle_env);
    let profile_id = resolve_profile_id(runtime, &args).await?;
    if handle.is_none() && profile_id.is_none() {
        bail!(
            "--handle or --profile is required (or run inside an Alera terminal where ALERA_TERMINAL_HANDLE is set)."
        );
    }
    let mut payload = json!({
        "workspaceId": workspace_id,
        "mode": if args.merge { "fixAndMerge" } else { "fix" },
        "checks": !args.no_checks,
        "comments": !args.no_comments,
        "conflicts": !args.no_conflicts,
    });
    if let Some(number) = args.review_number {
        payload["reviewNumber"] = json!(number);
    }
    if let Some(handle) = handle {
        payload["handle"] = json!(handle);
    }
    if let Some(profile_id) = profile_id {
        payload["profileId"] = json!(profile_id);
    }
    let watch = match backend(runtime).await? {
        Backend::Host(mut client) => {
            client
                .request_value("pullRequestWatch.start", &payload)
                .await?
        }
        Backend::Store(store) => {
            let watch = store_watch(&store, workspace_id, &payload).await?;
            serde_json::to_value(store.upsert_pull_request_watch(watch).await?)?
        }
    };
    crate::print_value(&watch, json_output, &watch_text(&watch));
    Ok(0)
}

async fn stop(runtime: &RuntimeDirArgs, workspace_id: &str, json_output: bool) -> Result<i32> {
    let removed = match backend(runtime).await? {
        Backend::Host(mut client) => client
            .request_value(
                "pullRequestWatch.stop",
                &json!({ "workspaceId": workspace_id }),
            )
            .await?["removed"]
            .as_bool()
            .unwrap_or(false),
        Backend::Store(store) => store.remove_pull_request_watch(workspace_id).await?,
    };
    crate::print_value(
        &json!({ "workspaceId": workspace_id, "removed": removed }),
        json_output,
        if removed {
            "stopped watching"
        } else {
            "not watching"
        },
    );
    Ok(0)
}

async fn resolve_profile_id(
    runtime: &RuntimeDirArgs,
    args: &WorkspacePrWatchStartArgs,
) -> Result<Option<String>> {
    if let Some(id) = args
        .profile_id
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        return Ok(Some(id.to_string()));
    }
    let Some(name) = args
        .profile
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    else {
        return Ok(None);
    };
    let dir = crate::runtime_dir(runtime);
    let profiles = if let Some(mut client) = RuntimeHostRpcClient::connect(&dir).await? {
        let payload = client
            .request_value("agentProfile.list", &json!({}))
            .await?;
        payload
            .get("items")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default()
    } else {
        RuntimeStore::open(&dir)
            .await?
            .list_agent_profiles()
            .await?
            .into_iter()
            .map(|profile| serde_json::to_value(profile).unwrap_or(Value::Null))
            .collect()
    };
    profiles
        .iter()
        .find(|profile| {
            profile
                .get("name")
                .and_then(Value::as_str)
                .is_some_and(|value| value.eq_ignore_ascii_case(name))
        })
        .and_then(|profile| profile.get("id").and_then(Value::as_str))
        .map(|id| id.to_string())
        .ok_or_else(|| anyhow!("agent profile not found: {name}"))
        .map(Some)
}

async fn store_watch(
    store: &RuntimeStore,
    workspace_id: &str,
    payload: &Value,
) -> Result<PullRequestWatch> {
    let workspace = store
        .find_workspace(workspace_id)
        .await?
        .ok_or_else(|| anyhow!("Workspace not found."))?;
    if workspace.status != WorkspaceStatus::Active {
        bail!("Workspace is not active.");
    }
    let review_number = match payload.get("reviewNumber").and_then(Value::as_i64) {
        Some(number) => number,
        None => store
            .find_linked_review(workspace_id)
            .await?
            .filter(|review| !review.dismissed)
            .and_then(|review| review.number)
            .filter(|number| *number > 0)
            .ok_or_else(|| anyhow!("Link or open a pull request for this workspace first."))?,
    };
    let tab_id = match payload.get("handle").and_then(Value::as_str) {
        Some(handle) => Some(tab_id_for_handle(store, workspace_id, handle).await?),
        None => None,
    };
    let profile_id = payload
        .get("profileId")
        .and_then(Value::as_str)
        .map(str::to_string);
    if let Some(id) = profile_id.as_deref() {
        store
            .find_agent_profile(id)
            .await?
            .ok_or_else(|| anyhow!("agent profile not found: {id}"))?;
    }
    Ok(PullRequestWatch {
        workspace_id: workspace_id.to_string(),
        review_number,
        mode: payload
            .get("mode")
            .and_then(Value::as_str)
            .unwrap_or("fix")
            .to_string(),
        checks: payload
            .get("checks")
            .and_then(Value::as_bool)
            .unwrap_or(true),
        comments: payload
            .get("comments")
            .and_then(Value::as_bool)
            .unwrap_or(true),
        conflicts: payload
            .get("conflicts")
            .and_then(Value::as_bool)
            .unwrap_or(true),
        tab_id,
        profile_id,
        label: None,
        last_dispatch: None,
        last_merged_head_sha: None,
    })
}

async fn tab_id_for_handle(
    store: &RuntimeStore,
    workspace_id: &str,
    handle: &str,
) -> Result<String> {
    for tab in store.list_workspace_tabs(workspace_id).await? {
        if tab_session_id(&tab).as_deref() == Some(handle) {
            return Ok(tab.id);
        }
    }
    bail!("Terminal handle not found. Start Watch and Fix while the runtime host is running.");
}

fn tab_session_id(tab: &alera_core::runtime::WorkspaceTabRecord) -> Option<String> {
    tab.payload
        .get("terminalSessionId")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

fn watch_text(watch: &Value) -> String {
    let mode = match watch.get("mode").and_then(Value::as_str) {
        Some("fixAndMerge") => "Watch, Fix and Merge",
        _ => "Watch and Fix",
    };
    let number = watch
        .get("reviewNumber")
        .and_then(Value::as_i64)
        .unwrap_or(0);
    let mut lines = vec![format!("{mode} on PR #{number}")];
    for (key, label) in [
        ("checks", "Failed Checks"),
        ("comments", "Review Comments"),
        ("conflicts", "Merge Conflicts"),
    ] {
        let enabled = watch.get(key).and_then(Value::as_bool).unwrap_or(false);
        lines.push(format!("{label}: {}", if enabled { "On" } else { "Off" }));
    }
    lines.join("\n")
}
