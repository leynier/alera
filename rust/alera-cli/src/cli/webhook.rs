use clap::{Args, Subcommand};

use super::{IdArgs, OutputArgs, RuntimeDirArgs};

/// Signed webhooks that receive this runtime's event journal through the
/// Alera cloud. Needs a signed-in account.
#[derive(Debug, Args)]
pub struct WebhookCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: WebhookAction,
}

#[derive(Debug, Subcommand)]
pub enum WebhookAction {
    /// List the account's webhooks.
    List,
    /// Add an HTTPS webhook. Prints its signing secret once.
    Add(WebhookAddArgs),
    /// Delete a webhook.
    Remove(IdArgs),
    /// Send a signed test delivery.
    Test(IdArgs),
}

#[derive(Debug, Args)]
pub struct WebhookAddArgs {
    /// HTTPS endpoint that receives signed POST requests.
    #[arg(long)]
    pub url: String,
    /// Event kinds to send, such as inbox.reply. Defaults to every kind.
    #[arg(long = "kind", value_delimiter = ',')]
    pub kinds: Vec<String>,
    /// Runtimes whose events it receives. Defaults to this runtime.
    #[arg(long = "runtime-id", value_delimiter = ',')]
    pub runtime_ids: Vec<String>,
}
