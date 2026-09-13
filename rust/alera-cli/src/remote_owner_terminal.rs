use alera_core::runtime::RuntimeStore;
use anyhow::{bail, Result};
use serde_json::json;

#[derive(Debug, clap::Args)]
pub(crate) struct RemoteOwnerTerminalArgs {
    #[command(flatten)]
    pub owner: crate::remote_workspace_owner::RemoteWorkspaceOwnerArgs,
    #[arg(long)]
    pub session_id: String,
    #[arg(long)]
    pub tab_id: String,
    #[arg(long)]
    pub automation_run_id: Option<String>,
    #[arg(long)]
    pub launch_token: Option<String>,
    #[arg(long, default_value_t = 80)]
    pub cols: u16,
    #[arg(long, default_value_t = 24)]
    pub rows: u16,
}

pub(crate) async fn run(args: RemoteOwnerTerminalArgs) -> Result<i32> {
    if args.tab_id.trim().is_empty()
        || args.session_id.trim().is_empty()
        || args.cols == 0
        || args.rows == 0
    {
        bail!("Stable terminal identities and nonzero dimensions are required");
    }
    let state_dir = args.owner.state_dir.clone();
    let registration = crate::remote_workspace_owner::parse_registration(&args.owner)?;
    let client = crate::runtime_host_client::RuntimeHostRpcClient::connect_or_start_with_required_capability(&state_dir, crate::terminal_host::protocol::RUNTIME_HOST_SHARED_CHECKOUT_CAPABILITY).await?;
    let store = RuntimeStore::open(&state_dir).await?;
    let workspace = crate::remote_workspace_owner::register(&store, registration).await?;
    crate::remote_owner_terminal_ownership::register_tab(
        &store,
        &workspace,
        &args.tab_id,
        &args.session_id,
        args.automation_run_id.as_deref(),
    )
    .await?;
    let launch = crate::terminal_host::server::terminal_launch_defaults::default_terminal_launch(
        &workspace.path,
        true,
    )
    .await;
    let (reader, writer, next_id) = client.into_terminal_transport();
    let _stdio = crate::terminal_stdio_mode::TerminalStdioMode::enter()?;
    let (cols, rows) = crate::terminal_stdio_mode::dimensions().unwrap_or((args.cols, args.rows));
    crate::remote_terminal_bridge::bridge(reader, writer, tokio::io::stdin(), tokio::io::stdout(), json!({
        "sessionId": args.session_id, "workspaceId": workspace.id, "tabId": args.tab_id,
        "workingDirectory": workspace.path, "launch": launch.launch.to_json(), "cols": cols, "rows": rows,
        "launchToken": args.launch_token,
    }), next_id, crate::terminal_stdio_mode::dimensions).await
}
