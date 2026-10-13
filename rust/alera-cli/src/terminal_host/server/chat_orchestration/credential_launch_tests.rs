use alera_provider_protocol::McpTransport;
use clap::Parser;

use crate::cli::{Cli, Command, McpAction};

use super::test_support::TestHarness;

#[tokio::test]
async fn injected_mcp_launch_parses_the_real_cli_with_its_runtime_and_credential() {
    let harness = TestHarness::new().await;
    let chat = harness.create_chat("ws-a", "approval-required").await;
    harness.control(&chat).await;
    let launch = harness
        .factory
        .launches
        .lock()
        .unwrap()
        .last()
        .unwrap()
        .clone();
    let server = launch
        .mcp_servers
        .iter()
        .find(|server| server.name == "alera")
        .unwrap();
    let McpTransport::Stdio {
        command,
        args,
        env,
        cwd,
    } = &server.transport
    else {
        panic!("the injected MCP server must use stdio");
    };
    assert_eq!(command, &std::env::current_exe().unwrap());
    assert!(env.is_empty());
    assert!(cwd.is_none());
    let cli = Cli::try_parse_from(
        std::iter::once(command.to_string_lossy().into_owned()).chain(args.iter().cloned()),
    )
    .expect("the production launch hook must emit arguments accepted by the real CLI");
    let Command::Mcp(mcp) = cli.command else {
        panic!("the launch must run the MCP command");
    };
    assert_eq!(
        mcp.runtime.runtime_dir.as_deref(),
        harness.directory.path().to_str()
    );
    let McpAction::Serve(serve) = mcp.action else {
        panic!("the launch must serve MCP over stdio");
    };
    assert_eq!(
        serve.chat_credential_file.as_ref(),
        launch.env.get("ALERA_CHAT_CREDENTIAL_FILE")
    );
    assert!(serve.chat_credential_file.is_some());
    harness.finish().await;
}
