//! `alera workspace prompt-start`: New Workspace from Prompt as a runtime
//! operation. `run` returns as soon as the runtime records the operation, or
//! after `--wait` seconds; `wait` follows it with bounded polling.

use std::time::{Duration, Instant};

use anyhow::Result;
use serde_json::{json, Value};

use crate::cli::{
    PromptStartModeArg, RuntimeDirArgs, WorkspacePromptStartAction, WorkspacePromptStartCommand,
    WorkspacePromptStartRunArgs,
};
use crate::mcp_tools::CallOrigin;
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::RUNTIME_HOST_PROMPT_WORKSPACE_SERVICE_CAPABILITY;
use crate::{print_error, print_value, runtime_dir};

const POLL_INTERVAL: Duration = Duration::from_secs(1);

pub async fn run(
    runtime: RuntimeDirArgs,
    command: WorkspacePromptStartCommand,
    json_output: bool,
) -> i32 {
    match run_inner(&runtime, command).await {
        Ok(value) => {
            print_value(&value, json_output, &summary(&value));
            0
        }
        Err(error) => print_error(error),
    }
}

async fn run_inner(
    runtime: &RuntimeDirArgs,
    command: WorkspacePromptStartCommand,
) -> Result<Value> {
    let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
        &runtime_dir(runtime),
        RUNTIME_HOST_PROMPT_WORKSPACE_SERVICE_CAPABILITY,
    )
    .await?;
    match command.action {
        WorkspacePromptStartAction::Run(args) => {
            let wait = args.wait;
            let started = client
                .request_value("workspace.promptStart.start", &start_payload(&args)?)
                .await?;
            if wait == 0 {
                return Ok(started);
            }
            let id = started["id"].as_str().unwrap_or_default().to_owned();
            wait_for(&mut client, &id, Duration::from_secs(wait)).await
        }
        WorkspacePromptStartAction::Show(args) => {
            client
                .request_value("workspace.promptStart.get", &json!({ "id": args.id }))
                .await
        }
        WorkspacePromptStartAction::List(args) => {
            client
                .request_value(
                    "workspace.promptStart.list",
                    &json!({ "limit": args.limit }),
                )
                .await
        }
        WorkspacePromptStartAction::Wait(args) => {
            wait_for(
                &mut client,
                &args.id,
                Duration::from_secs(args.timeout_seconds),
            )
            .await
        }
        WorkspacePromptStartAction::Cancel(args) => {
            client
                .request_value("workspace.promptStart.cancel", &json!({ "id": args.id }))
                .await
        }
        WorkspacePromptStartAction::RetryLaunch(args) => {
            client
                .request_value(
                    "workspace.promptStart.retryLaunch",
                    &json!({ "id": args.id }),
                )
                .await
        }
    }
}

pub(crate) fn start_payload(args: &WorkspacePromptStartRunArgs) -> Result<Value> {
    let section = match (
        args.section_id.as_deref(),
        args.section.as_deref().map(str::trim),
    ) {
        (Some(id), _) => json!({ "id": id }),
        (None, None | Some("auto")) => json!("auto"),
        (None, Some("none")) => json!("none"),
        (None, Some(name)) => json!({ "name": name }),
    };
    let mode = match args.mode {
        PromptStartModeArg::Auto => "auto",
        PromptStartModeArg::Worktree => "worktree",
        PromptStartModeArg::ProjectCheckout => "projectCheckout",
    };
    Ok(json!({
        "prompt": args.prompt.read()?,
        "projectId": args.project_id,
        "profile": args.profile,
        "mode": mode,
        "sourceBranch": args.source_branch,
        "hostId": args.host_id,
        "parentWorkspaceId": args.parent_workspace_id,
        "issueUrl": args.issue_url,
        "section": section,
        "requestId": args.request_id,
        "origin": CallOrigin::from_env(),
    }))
}

/// Polls until the operation stops running or the time is up, then returns
/// its latest state either way.
async fn wait_for(client: &mut RuntimeHostRpcClient, id: &str, timeout: Duration) -> Result<Value> {
    let deadline = Instant::now() + timeout;
    loop {
        let operation = client
            .request_value("workspace.promptStart.get", &json!({ "id": id }))
            .await?;
        let running = operation["status"] == "running";
        let now = Instant::now();
        if !running || now >= deadline {
            return Ok(operation);
        }
        tokio::time::sleep(POLL_INTERVAL.min(deadline - now)).await;
    }
}

fn summary(value: &Value) -> String {
    if let Some(items) = value["items"].as_array() {
        return format!("{} prompt workspace operation(s)", items.len());
    }
    let status = value["status"].as_str().unwrap_or("unknown");
    let phase = value["phase"].as_str().unwrap_or_default();
    let mut line = format!(
        "operation {}: {status}",
        value["id"].as_str().unwrap_or("?")
    );
    if status == "running" {
        line.push_str(&format!(" ({phase})"));
    }
    if let Some(name) = value["workspace"]["name"].as_str() {
        line.push_str(&format!(", workspace {name}"));
    }
    if let Some(message) = value["error"]["message"].as_str() {
        line.push_str(&format!(": {message}"));
    }
    line
}

#[cfg(test)]
mod tests {
    use clap::Parser;
    use serde_json::json;

    use super::start_payload;
    use crate::cli::{Cli, Command, WorkspaceAction, WorkspacePromptStartAction};

    fn run_args(extra: &[&str]) -> crate::cli::WorkspacePromptStartRunArgs {
        let mut argv = vec![
            "alera",
            "workspace",
            "prompt-start",
            "run",
            "--prompt",
            "Fix login",
        ];
        argv.extend_from_slice(extra);
        let Command::Workspace(command) = Cli::try_parse_from(argv).unwrap().command else {
            panic!("expected a workspace command");
        };
        let WorkspaceAction::PromptStart(prompt_start) = command.action else {
            panic!("expected prompt-start");
        };
        let WorkspacePromptStartAction::Run(args) = prompt_start.action else {
            panic!("expected run");
        };
        *args
    }

    #[test]
    fn sections_map_to_the_runtime_policy() {
        assert_eq!(
            start_payload(&run_args(&[])).unwrap()["section"],
            json!("auto")
        );
        assert_eq!(
            start_payload(&run_args(&["--section", "none"])).unwrap()["section"],
            json!("none")
        );
        assert_eq!(
            start_payload(&run_args(&["--section", "Alera"])).unwrap()["section"],
            json!({ "name": "Alera" })
        );
        assert_eq!(
            start_payload(&run_args(&["--section-id", "s-1"])).unwrap()["section"],
            json!({ "id": "s-1" })
        );
    }

    #[test]
    fn modes_use_the_runtime_spelling() {
        let payload = start_payload(&run_args(&["--mode", "project-checkout"])).unwrap();
        assert_eq!(payload["mode"], "projectCheckout");
        assert_eq!(payload["prompt"], "Fix login");
        assert_eq!(start_payload(&run_args(&[])).unwrap()["mode"], "auto");
    }
}
