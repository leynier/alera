//! `alera chat pr link|unlink|list|watch|unwatch`: pull requests linked to a
//! chat (`chatOrchestrationPullRequestsV1`).

use anyhow::Result;
use clap::{Args, Subcommand};
use serde_json::{json, Value};

use crate::cli::RuntimeDirArgs;

pub(crate) const PULL_REQUESTS_CAPABILITY: &str = "chatOrchestrationPullRequestsV1";

#[derive(Debug, Args)]
pub struct ChatPullRequestArgs {
    #[command(subcommand)]
    pub action: ChatPullRequestAction,
}

#[derive(Debug, Subcommand)]
pub enum ChatPullRequestAction {
    /// Link a pull request to the chat.
    Link(ChatPullRequestTarget),
    /// Remove a pull request link; succeeds when it was not linked.
    Unlink(ChatPullRequestTarget),
    /// List the chat's linked pull requests.
    List(ChatPullRequestChat),
    /// Watch an open pull request, linking it first; delegated children
    /// cannot watch.
    Watch(ChatPullRequestTarget),
    /// Stop watching a pull request; it stays linked.
    Unwatch(ChatPullRequestTarget),
}

#[derive(Debug, Args)]
pub struct ChatPullRequestTarget {
    /// The pull request's web URL.
    #[arg(long)]
    pub url: String,
    /// The chat; the bound chat when omitted.
    #[arg(long = "chat-id")]
    pub chat_id: Option<String>,
    #[arg(long = "request-id")]
    pub request_id: Option<String>,
}

#[derive(Debug, Args)]
pub struct ChatPullRequestChat {
    #[arg(long = "chat-id")]
    pub chat_id: Option<String>,
}

fn chat(chat_id: Option<String>) -> Option<String> {
    chat_id
        .map(|chat_id| chat_id.trim().to_owned())
        .filter(|chat_id| !chat_id.is_empty())
}

pub(crate) async fn run(runtime: &RuntimeDirArgs, args: ChatPullRequestArgs) -> Result<Value> {
    let (verb, payload) = match args.action {
        ChatPullRequestAction::List(target) => {
            ("listPullRequests", json!({"chatId": chat(target.chat_id)}))
        }
        ChatPullRequestAction::Link(target) => ("linkPullRequest", target_payload(target)),
        ChatPullRequestAction::Unlink(target) => ("unlinkPullRequest", target_payload(target)),
        ChatPullRequestAction::Watch(target) => ("watchPullRequest", target_payload(target)),
        ChatPullRequestAction::Unwatch(target) => ("unwatchPullRequest", target_payload(target)),
    };
    crate::chat_orchestration_request::request(
        runtime,
        &format!("chatOrchestration.{verb}"),
        payload,
        None,
    )
    .await
}

fn target_payload(target: ChatPullRequestTarget) -> Value {
    let mut payload = json!({"url": target.url.trim(), "chatId": chat(target.chat_id)});
    if let Some(request_id) = chat(target.request_id) {
        payload["requestId"] = json!(request_id);
    }
    payload
}
