//! `alera pr`: thin JSON clients of the runtime's pull request verbs
//! (`mobile.pullRequest.*`, `aiText.pullRequestDetails.generate`,
//! `pullRequest.agentDispatch`, `pullRequestStack.*`, `pullRequestWatch.start`),
//! so the CLI and MCP see exactly what the phone and desktop see on GitHub,
//! GitLab, and Azure DevOps.

use std::io::Read;

use anyhow::{anyhow, bail, Result};
use serde_json::{json, Value};

use crate::cli::{
    PrAgentTargetArgs, PrBodyArgs, PrDispatchArgs, PrNumberArgs, PrShipArgs, PrTargetArgs,
    PrWatchMode, PullRequestAction, PullRequestCommand, RuntimeDirArgs,
};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::{
    RUNTIME_HOST_PULL_REQUEST_AGENT_DISPATCH_CAPABILITY,
    RUNTIME_HOST_PULL_REQUEST_FORGES_CAPABILITY,
};
use crate::workspace_context::resolve_requested_workspace_id;
use crate::{print_error, print_value, runtime_dir};

#[path = "pull_request_stack_commands.rs"]
mod stack;

pub async fn run(command: PullRequestCommand) -> i32 {
    let json_output = command.output.json;
    match execute(&command.runtime, command.action).await {
        Ok((value, message)) => {
            print_value(&value, json_output, &message);
            0
        }
        Err(error) => print_error(error),
    }
}

async fn execute(runtime: &RuntimeDirArgs, action: PullRequestAction) -> Result<(Value, String)> {
    match action {
        PullRequestAction::Show(target) => {
            let mut session = Session::open(runtime, &target).await?;
            let snapshot = session.snapshot().await?;
            let message = review_line(&snapshot);
            Ok((snapshot, message))
        }
        PullRequestAction::Summaries(target) => {
            let mut client = forge_client(runtime).await?;
            let mut value = client
                .request_value("mobile.pullRequest.summaries", &json!({}))
                .await?;
            if let Some(id) = target.workspace_id.as_deref() {
                if let Some(items) = value["summaries"].as_array_mut() {
                    items.retain(|item| item["workspaceId"] == id);
                }
            }
            let count = value["summaries"].as_array().map_or(0, Vec::len);
            Ok((value, format!("{count} pull request summary(ies)")))
        }
        PullRequestAction::GenerateDetails(args) => {
            let session = Session::open(runtime, &args.target).await?;
            let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
                &runtime_dir(runtime),
                crate::terminal_host::ai_assist_capabilities::RUNTIME_HOST_AI_ASSIST_PULL_REQUEST_DETAILS_CAPABILITY,
            )
            .await?;
            let value = client
                .request_value(
                    "aiText.pullRequestDetails.generate",
                    &json!({
                        "operationId": format!("cli-{}", uuid::Uuid::new_v4()),
                        "workspaceId": session.workspace_id,
                        "baseBranch": args.base.trim(),
                    }),
                )
                .await?;
            let message = value["title"].as_str().unwrap_or_default().to_string();
            Ok((value, message))
        }
        PullRequestAction::Create(args) => {
            let mut session = Session::open(runtime, &args.base.target).await?;
            let payload = json!({
                "baseBranch": args.base.base.trim(),
                "title": args.title,
                "body": read_body(&args.body, false)?,
                "draft": args.draft,
            });
            session.write("mobile.pullRequest.create", payload).await
        }
        PullRequestAction::Link(args) => {
            let mut session = Session::open(runtime, &args.target).await?;
            session
                .write(
                    "mobile.pullRequest.link",
                    json!({ "reference": args.reference }),
                )
                .await
        }
        PullRequestAction::Unlink(args) => {
            let mut session = Session::open(runtime, &args.target).await?;
            let snapshot = session.snapshot().await?;
            let number = args
                .number
                .or_else(|| snapshot["review"]["number"].as_i64())
                .or_else(|| snapshot["linkedReview"]["number"].as_i64())
                .ok_or_else(no_review)?;
            let url = snapshot["review"]["url"].clone();
            session
                .write(
                    "mobile.pullRequest.unlink",
                    json!({ "number": number, "url": url }),
                )
                .await
        }
        PullRequestAction::Comment(args) => {
            let mut session = Session::open(runtime, &args.number.target).await?;
            let number = session.number(&args.number).await?;
            let mut payload = json!({ "number": number, "body": read_body(&args.body, true)? });
            if let Some(reply_to) = args.reply_to {
                payload["replyToCommentId"] = json!(reply_to);
                payload["replyToThreadId"] = json!(args.thread_id);
            }
            session.write("mobile.pullRequest.comment", payload).await
        }
        PullRequestAction::CommentEdit(args) => {
            let mut session = Session::open(runtime, &args.number.target).await?;
            let number = session.number(&args.number).await?;
            let payload = json!({
                "number": number,
                "commentId": args.comment_id,
                "source": args.source.wire(),
                "threadId": args.thread_id,
                "body": read_body(&args.body, true)?,
            });
            session
                .write("mobile.pullRequest.commentUpdate", payload)
                .await
        }
        PullRequestAction::Draft(args) => {
            let mut session = Session::open(runtime, &args.number.target).await?;
            let number = session.number(&args.number).await?;
            let payload = json!({ "number": number, "draft": !args.ready });
            session
                .write("mobile.pullRequest.draftStatus", payload)
                .await
        }
        PullRequestAction::Close(args) => {
            let mut session = Session::open(runtime, &args.target).await?;
            let number = session.number(&args).await?;
            session
                .write("mobile.pullRequest.close", json!({ "number": number }))
                .await
        }
        PullRequestAction::Merge(args) => {
            let mut session = Session::open(runtime, &args.number.target).await?;
            let snapshot = session.snapshot().await?;
            let number = args
                .number
                .number
                .or_else(|| snapshot["review"]["number"].as_i64())
                .ok_or_else(no_review)?;
            let method = match args.method {
                Some(method) => method.wire().to_string(),
                None => preferred_method(&snapshot)?,
            };
            let payload = json!({
                "number": number,
                "method": method,
                "expectedHeadSha": args.expected_head,
            });
            session.write("mobile.pullRequest.merge", payload).await
        }
        PullRequestAction::Ship(args) => ship(runtime, args).await,
        PullRequestAction::Restack(args) => dispatch(runtime, "restack", args).await,
        PullRequestAction::FixChecks(args) => dispatch(runtime, "fixFailedChecks", args).await,
        PullRequestAction::Stack(command) => stack::run(runtime, command.action).await,
    }
}

/// One workspace's pull request verbs over one runtime connection.
pub(crate) struct Session {
    pub(crate) workspace_id: String,
    pub(crate) client: RuntimeHostRpcClient,
}

impl Session {
    pub(crate) async fn open(runtime: &RuntimeDirArgs, target: &PrTargetArgs) -> Result<Self> {
        let workspace_id = resolve_requested_workspace_id(runtime, target.workspace_id.as_deref())
            .await?
            .ok_or_else(|| {
                anyhow!("--workspace-id is required (or run inside an Alera terminal where ALERA_WORKSPACE_ID is set).")
            })?;
        Ok(Self {
            workspace_id,
            client: forge_client(runtime).await?,
        })
    }

    pub(crate) async fn snapshot(&mut self) -> Result<Value> {
        self.client
            .request_value(
                "mobile.pullRequest.snapshot",
                &json!({ "workspaceId": self.workspace_id }),
            )
            .await
    }

    /// [args]'s number, or the review the snapshot shows.
    pub(crate) async fn number(&mut self, args: &PrNumberArgs) -> Result<i64> {
        if let Some(number) = args.number {
            return Ok(number);
        }
        self.snapshot().await?["review"]["number"]
            .as_i64()
            .ok_or_else(no_review)
    }

    /// Runs a write verb; the answer is the refreshed snapshot.
    pub(crate) async fn write(
        &mut self,
        verb: &str,
        mut payload: Value,
    ) -> Result<(Value, String)> {
        payload["workspaceId"] = json!(self.workspace_id);
        let value = self.client.request_value(verb, &payload).await?;
        let message = review_line(&value);
        Ok((value, message))
    }
}

async fn forge_client(runtime: &RuntimeDirArgs) -> Result<RuntimeHostRpcClient> {
    RuntimeHostRpcClient::connect_or_start_with_required_capability(
        &runtime_dir(runtime),
        RUNTIME_HOST_PULL_REQUEST_FORGES_CAPABILITY,
    )
    .await
}

fn no_review() -> anyhow::Error {
    anyhow!("No pull request is linked to this workspace or open for its branch. Pass --number.")
}

/// The method an unattended merge uses: the forge's default, else the first allowed.
fn preferred_method(snapshot: &Value) -> Result<String> {
    let methods = snapshot["mergeMethods"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .collect::<Vec<_>>();
    if methods.contains(&"providerDefault") {
        return Ok("providerDefault".into());
    }
    methods
        .first()
        .map(|method| method.to_string())
        .ok_or_else(|| {
            anyhow!("The forge offers no merge method for this pull request. Pass --method.")
        })
}

fn read_body(args: &PrBodyArgs, required: bool) -> Result<String> {
    let body = if args.body_stdin {
        let mut text = String::new();
        std::io::stdin().read_to_string(&mut text)?;
        text
    } else {
        args.body.clone().unwrap_or_default()
    };
    if required && body.trim().is_empty() {
        bail!("--body or --body-stdin is required.");
    }
    Ok(body)
}

pub(crate) fn review_line(snapshot: &Value) -> String {
    let review = &snapshot["review"];
    match review["number"].as_i64() {
        Some(number) => format!(
            "#{number} {} ({})",
            review["title"].as_str().unwrap_or(""),
            review["state"].as_str().unwrap_or("")
        ),
        None => snapshot["unavailableReason"]
            .as_str()
            .unwrap_or("No pull request.")
            .to_string(),
    }
}

/// Agent profile id from --profile-id, or looked up by --profile name.
pub(crate) async fn profile_id(
    client: &mut RuntimeHostRpcClient,
    agent: &PrAgentTargetArgs,
) -> Result<Option<String>> {
    if let Some(id) = agent
        .profile_id
        .as_deref()
        .map(str::trim)
        .filter(|id| !id.is_empty())
    {
        return Ok(Some(id.to_string()));
    }
    let Some(name) = agent
        .profile
        .as_deref()
        .map(str::trim)
        .filter(|name| !name.is_empty())
    else {
        return Ok(None);
    };
    let profiles = client
        .request_value("agentProfile.list", &json!({}))
        .await?;
    profiles["items"]
        .as_array()
        .into_iter()
        .flatten()
        .find(|profile| {
            profile["name"]
                .as_str()
                .is_some_and(|value| value.eq_ignore_ascii_case(name))
        })
        .and_then(|profile| profile["id"].as_str())
        .map(|id| Some(id.to_string()))
        .ok_or_else(|| anyhow!("agent profile not found: {name}"))
}

async fn dispatch(
    runtime: &RuntimeDirArgs,
    kind: &str,
    args: PrDispatchArgs,
) -> Result<(Value, String)> {
    let workspace_id =
        resolve_requested_workspace_id(runtime, args.number.target.workspace_id.as_deref())
            .await?
            .ok_or_else(|| anyhow!("--workspace-id is required (or run inside an Alera terminal where ALERA_WORKSPACE_ID is set)."))?;
    let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
        &runtime_dir(runtime),
        RUNTIME_HOST_PULL_REQUEST_AGENT_DISPATCH_CAPABILITY,
    )
    .await?;
    let mut payload =
        json!({ "workspaceId": workspace_id, "kind": kind, "number": args.number.number });
    if kind == "fixFailedChecks" && args.number.number.is_none() {
        let snapshot = client
            .request_value(
                "mobile.pullRequest.snapshot",
                &json!({ "workspaceId": workspace_id }),
            )
            .await?;
        payload["number"] = snapshot["review"]["number"].clone();
    }
    if !args.preview {
        let handle = args
            .agent
            .handle
            .clone()
            .or_else(crate::orchestration_commands::terminal_handle_env);
        let profile = profile_id(&mut client, &args.agent).await?;
        if handle.is_none() && args.agent.tab_id.is_none() && profile.is_none() {
            bail!("--handle, --tab-id, or --profile is required (or run inside an Alera terminal where ALERA_TERMINAL_HANDLE is set). Use --preview to print the prompt only.");
        }
        payload["handle"] = json!(handle);
        payload["tabId"] = json!(args.agent.tab_id);
        payload["profileId"] = json!(profile);
    }
    let value = client
        .request_value("pullRequest.agentDispatch", &payload)
        .await?;
    let message = if value["dispatched"] == true {
        format!(
            "Sent {} to the agent",
            value["title"].as_str().unwrap_or("the prompt")
        )
    } else {
        value["prompt"].as_str().unwrap_or_default().to_string()
    };
    Ok((value, message))
}

async fn ship(runtime: &RuntimeDirArgs, args: PrShipArgs) -> Result<(Value, String)> {
    let mut session = Session::open(runtime, &args.base.target).await?;
    let mut watch_payload = None;
    if let Some(mode) = args.follow_up_watch {
        if args.no_checks && args.no_comments && args.no_conflicts {
            bail!("Choose at least one of checks, comments, or conflicts.");
        }
        // Resolve the agent first, so a bad target fails before anything ships.
        let handle = args
            .agent
            .handle
            .clone()
            .or_else(crate::orchestration_commands::terminal_handle_env);
        let profile = profile_id(&mut session.client, &args.agent).await?;
        if handle.is_none() && args.agent.tab_id.is_none() && profile.is_none() {
            bail!("--handle, --tab-id, or --profile is required for --follow-up-watch (or run inside an Alera terminal where ALERA_TERMINAL_HANDLE is set).");
        }
        watch_payload = Some(json!({
            "workspaceId": session.workspace_id,
            "mode": match mode { PrWatchMode::Fix => "fix", PrWatchMode::FixAndMerge => "fixAndMerge" },
            "checks": !args.no_checks,
            "comments": !args.no_comments,
            "conflicts": !args.no_conflicts,
            "handle": handle,
            "tabId": args.agent.tab_id,
            "profileId": profile,
        }));
    }
    let payload = json!({
        "baseBranch": args.base.base.trim(),
        "draft": args.draft,
        "scope": match args.scope { crate::cli::PrShipScope::All => "all", crate::cli::PrShipScope::Staged => "staged" },
    });
    let (mut value, mut message) = session.write("mobile.pullRequest.ship", payload).await?;
    if let Some(mut watch) = watch_payload {
        let Some(number) = value["review"]["number"].as_i64() else {
            value["followUpWatch"] = json!({ "started": false, "error": "The new pull request could not be read back; start Watch and Fix with alera workspace pr-watch start." });
            return Ok((value, message));
        };
        watch["reviewNumber"] = json!(number);
        match session
            .client
            .request_value("pullRequestWatch.start", &watch)
            .await
        {
            Ok(started) => {
                value["followUpWatch"] = json!({ "started": true, "watch": started });
                message.push_str("\nWatching the pull request");
            }
            Err(error) => {
                value["followUpWatch"] = json!({ "started": false, "error": error.to_string() });
            }
        }
    }
    Ok((value, message))
}
