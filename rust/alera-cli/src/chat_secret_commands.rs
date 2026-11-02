//! `alera chat request-secret` and `alera chat secret read`
//! (`agentChatSecretRequestsV1`). `secret read` is for use inside another
//! command, such as `TOKEN="$(alera chat secret read --ref "$REF")"`: it
//! prints the bare value once and spends the ref.

use anyhow::Result;
use clap::{Args, Subcommand};
use serde_json::{json, Value};

use crate::cli::RuntimeDirArgs;
use crate::orchestration_commands::WAIT_CLIENT_GRACE_MS;

/// `chatOrchestration.requestSecret`, `chatOrchestration.readSecret` and
/// `agentChat.secret.provide`.
pub(crate) const SECRET_REQUESTS_CAPABILITY: &str = "agentChatSecretRequestsV1";

/// The host waits up to 45 s before it answers `pending`.
const REQUEST_SECRET_DEADLINE_MS: u64 = 45_000 + WAIT_CLIENT_GRACE_MS;

#[derive(Debug, Args)]
pub struct ChatRequestSecretArgs {
    /// Card title, such as "GitHub webhook secret".
    #[arg(long)]
    pub label: Option<String>,
    /// What it is for and where to get it.
    #[arg(long)]
    pub reason: Option<String>,
    #[arg(long)]
    pub placeholder: Option<String>,
    /// `file` (default) or `ref`.
    #[arg(long)]
    pub delivery: Option<String>,
    /// Keep waiting on a request a `pending` answer named.
    #[arg(long = "secret-request-id")]
    pub secret_request_id: Option<String>,
}

#[derive(Debug, Args)]
pub struct ChatSecretArgs {
    #[command(subcommand)]
    pub action: ChatSecretAction,
}

#[derive(Debug, Subcommand)]
pub enum ChatSecretAction {
    /// Print a one-use secretRef's value and spend it.
    Read(ChatSecretReadArgs),
}

#[derive(Debug, Args)]
pub struct ChatSecretReadArgs {
    #[arg(long = "ref")]
    pub secret_ref: String,
}

fn optional(value: Option<String>) -> Option<String> {
    value
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
}

pub(crate) async fn request_secret(
    runtime: &RuntimeDirArgs,
    args: ChatRequestSecretArgs,
) -> Result<Value> {
    let mut payload = json!({});
    for (key, value) in [
        ("label", optional(args.label)),
        ("reason", optional(args.reason)),
        ("placeholder", optional(args.placeholder)),
        ("delivery", optional(args.delivery)),
        ("secretRequestId", optional(args.secret_request_id)),
    ] {
        if let Some(value) = value {
            payload[key] = json!(value);
        }
    }
    crate::chat_orchestration_request::request(
        runtime,
        "chatOrchestration.requestSecret",
        payload,
        Some(REQUEST_SECRET_DEADLINE_MS),
    )
    .await
}

/// Prints the bare value to stdout, never as JSON, so a command substitution
/// reads it as is.
pub(crate) async fn secret(runtime: &RuntimeDirArgs, args: ChatSecretArgs) -> i32 {
    let ChatSecretAction::Read(read) = args.action;
    let result = crate::chat_orchestration_request::request(
        runtime,
        "chatOrchestration.readSecret",
        json!({"secretRef": read.secret_ref.trim()}),
        None,
    )
    .await;
    match result {
        Ok(value) => match value["value"].as_str() {
            Some(secret) => {
                use std::io::Write as _;
                let mut stdout = std::io::stdout();
                if stdout.write_all(secret.as_bytes()).is_err() || stdout.flush().is_err() {
                    return 1;
                }
                0
            }
            None => crate::print_error(anyhow::anyhow!("The host returned no secret.")),
        },
        Err(error) => crate::print_error(error),
    }
}
