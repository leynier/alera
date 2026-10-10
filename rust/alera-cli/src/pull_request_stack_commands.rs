//! `alera pr stack show|create|link|merge` over `pullRequestStack.*`. GitHub
//! only, like the desktop; other forges answer `provider_unsupported`.

use anyhow::{anyhow, Result};
use serde_json::{json, Value};

use crate::cli::{PrStackAction, PrTargetArgs, RuntimeDirArgs};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::RUNTIME_HOST_PULL_REQUEST_STACKS_CAPABILITY;
use crate::workspace_context::resolve_requested_workspace_id;

pub(super) async fn run(
    runtime: &RuntimeDirArgs,
    action: PrStackAction,
) -> Result<(Value, String)> {
    let (verb, target, payload) = match action {
        PrStackAction::Show(args) => (
            "pullRequestStack.get",
            args.target,
            json!({ "number": args.number }),
        ),
        PrStackAction::Create(args) => {
            let layers = args
                .layers
                .iter()
                .enumerate()
                .map(|(index, workspace_id)| {
                    json!({
                        "workspaceId": workspace_id,
                        "title": args.titles.get(index),
                        "draft": args.draft,
                    })
                })
                .collect::<Vec<_>>();
            (
                "pullRequestStack.create",
                args.target,
                json!({ "baseBranch": args.base, "layers": layers }),
            )
        }
        PrStackAction::Link(args) => (
            "pullRequestStack.link",
            args.target,
            json!({ "numbers": args.numbers }),
        ),
        PrStackAction::Merge(args) => (
            "pullRequestStack.merge",
            args.number.target,
            json!({
                "number": args.number.number,
                "method": args.method.map(|method| method.wire()),
            }),
        ),
    };
    let value = request(runtime, &target, verb, payload).await?;
    Ok((value.clone(), stack_line(&value)))
}

async fn request(
    runtime: &RuntimeDirArgs,
    target: &PrTargetArgs,
    verb: &str,
    mut payload: Value,
) -> Result<Value> {
    let workspace_id = resolve_requested_workspace_id(runtime, target.workspace_id.as_deref())
        .await?
        .ok_or_else(|| {
            anyhow!("--workspace-id is required (or run inside an Alera terminal where ALERA_WORKSPACE_ID is set).")
        })?;
    payload["workspaceId"] = json!(workspace_id);
    let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
        &crate::runtime_dir(runtime),
        RUNTIME_HOST_PULL_REQUEST_STACKS_CAPABILITY,
    )
    .await?;
    client.request_value(verb, &payload).await
}

fn stack_line(value: &Value) -> String {
    if value["merged"] == true {
        return format!("Merged the stack through #{}", value["reviewNumber"]);
    }
    let stack = &value["stack"];
    let Some(number) = stack["number"].as_i64() else {
        return "The pull request is not in a stack.".to_string();
    };
    let members = stack["entries"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|entry| entry["review"]["number"].as_i64())
        .map(|number| format!("#{number}"))
        .collect::<Vec<_>>();
    format!("Stack {number}: {}", members.join(" <- "))
}
