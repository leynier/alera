//! `alera mcp`, `alera account`, and `alera runtime rename`.
//!
//! Everything that touches the cloud runs inside the runtime host, which owns
//! the account credential and the relay link, so these commands start it when
//! needed and send it host requests.

use std::path::Path;
use std::time::Duration;

use anyhow::{anyhow, bail, Result};
use serde_json::{json, Value};

use crate::cli::{
    AccountAction, AccountCommand, AccountLoginArgs, AccountProviderArg, McpAction, McpCommand,
};
use crate::mcp_tools::{catalog, catalog_json, serve_stdio, ToolExecution};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::{print_error, print_value, runtime_dir};

const CLOUD_DEADLINE_MS: u64 = 30_000;
const SIGN_IN_TIMEOUT: Duration = Duration::from_secs(15 * 60);
/// The remote MCP endpoint of the cloud this runtime signs in to.
pub(crate) fn mcp_endpoint() -> String {
    let base = std::env::var("ALERA_CLOUD_URL")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| "https://api.alera.build".to_owned());
    format!("{}/v1/mcp", base.trim_end_matches('/'))
}

pub(crate) async fn run_mcp(command: McpCommand) -> i32 {
    let runtime_dir = runtime_dir(&command.runtime);
    let json_output = command.output.json;
    let action = command.action_name();
    let result = match command.action {
        McpAction::Status => mcp_status(&runtime_dir).await,
        McpAction::Enable(args) => {
            let access = if args.read_only { "read" } else { "full" };
            update_settings(&runtime_dir, json!({ "access": access })).await
        }
        McpAction::Disable => update_settings(&runtime_dir, json!({ "access": "off" })).await,
        McpAction::Apps => host_request(&runtime_dir, "mcp.grants.list", json!({})).await,
        McpAction::Revoke(args) => {
            host_request(
                &runtime_dir,
                "mcp.grants.revoke",
                json!({ "grantId": args.grant_id }),
            )
            .await
        }
        McpAction::Tools => Ok(catalog_json()),
        McpAction::Serve(args) => {
            return match ToolExecution::current(runtime_dir) {
                Ok(execution) => match serve_stdio(execution, args.read_only).await {
                    Ok(()) => 0,
                    Err(error) => print_error(error),
                },
                Err(error) => print_error(error),
            };
        }
    };
    match result {
        Ok(value) => {
            let message = match action {
                "apps" => apps_message(&value),
                "tools" => tools_message(),
                "revoke" => "connected app revoked".to_owned(),
                _ => settings_message(&value),
            };
            print_value(&value, json_output, &message);
            0
        }
        Err(error) => print_error(error),
    }
}

impl McpCommand {
    fn action_name(&self) -> &'static str {
        match self.action {
            McpAction::Status => "status",
            McpAction::Enable(_) => "enable",
            McpAction::Disable => "disable",
            McpAction::Apps => "apps",
            McpAction::Revoke(_) => "revoke",
            McpAction::Tools => "tools",
            McpAction::Serve(_) => "serve",
        }
    }
}

pub(crate) async fn run_account(command: AccountCommand) -> i32 {
    let runtime_dir = runtime_dir(&command.runtime);
    let json_output = command.output.json;
    let result = match command.action {
        AccountAction::Status => account_status(&runtime_dir).await,
        AccountAction::Login(args) => account_login(&runtime_dir, args, json_output).await,
        AccountAction::Logout => host_request(&runtime_dir, "account.signOut", json!({})).await,
    };
    match result {
        Ok(value) => {
            let message = match value["account"]["email"].as_str() {
                Some(email) => format!("signed in as {email}"),
                None => "not signed in".to_owned(),
            };
            print_value(&value, json_output, &message);
            0
        }
        Err(error) => print_error(error),
    }
}

pub(crate) async fn rename_runtime(runtime_dir: &Path, name: String, json_output: bool) -> i32 {
    match update_settings(runtime_dir, json!({ "runtimeName": name })).await {
        Ok(value) => {
            let message = format!(
                "runtime renamed to {}",
                value["effectiveRuntimeName"].as_str().unwrap_or_default()
            );
            print_value(&value, json_output, &message);
            0
        }
        Err(error) => print_error(error),
    }
}

async fn mcp_status(runtime_dir: &Path) -> Result<Value> {
    match RuntimeHostRpcClient::connect(runtime_dir).await? {
        Some(mut client) => {
            let mut value = client
                .request_value_with_deadline("mcp.settings.get", &json!({}), CLOUD_DEADLINE_MS)
                .await?;
            value["endpoint"] = json!(mcp_endpoint());
            value["runtimeHost"] = json!(true);
            Ok(value)
        }
        None => {
            let store = alera_core::runtime::RuntimeStore::open(runtime_dir).await?;
            Ok(json!({
                "access": crate::mcp_settings::mcp_access(&store).await?.as_str(),
                "runtimeName": crate::mcp_settings::runtime_name(&store).await?,
                "effectiveRuntimeName": crate::mcp_settings::effective_runtime_name(&store).await,
                "accountConnected": store.alera_account().await?.is_some(),
                "endpoint": mcp_endpoint(),
                "runtimeHost": false,
            }))
        }
    }
}

async fn update_settings(runtime_dir: &Path, payload: Value) -> Result<Value> {
    let mut value = host_request(runtime_dir, "mcp.settings.update", payload).await?;
    value["endpoint"] = json!(mcp_endpoint());
    Ok(value)
}

async fn host_request(runtime_dir: &Path, request_type: &str, payload: Value) -> Result<Value> {
    let mut client = RuntimeHostRpcClient::connect_or_start_persistent(runtime_dir).await?;
    client
        .request_value_with_deadline(request_type, &payload, CLOUD_DEADLINE_MS)
        .await
}

async fn account_status(runtime_dir: &Path) -> Result<Value> {
    match RuntimeHostRpcClient::connect(runtime_dir).await? {
        Some(mut client) => client.request_value("account.status", &json!({})).await,
        None => {
            let store = alera_core::runtime::RuntimeStore::open(runtime_dir).await?;
            let account = store.alera_account().await?;
            Ok(json!({ "connected": account.is_some(), "account": account }))
        }
    }
}

async fn account_login(runtime_dir: &Path, args: AccountLoginArgs, quiet: bool) -> Result<Value> {
    let mut client = RuntimeHostRpcClient::connect_or_start_persistent(runtime_dir).await?;
    let started = if args.device {
        client
            .request_value_with_deadline(
                "account.signIn.device.start",
                &json!({}),
                CLOUD_DEADLINE_MS,
            )
            .await?
    } else {
        let provider = match args.provider {
            AccountProviderArg::Github => "github",
            AccountProviderArg::Google => "google",
        };
        client
            .request_value_with_deadline(
                "account.signIn.start",
                &json!({ "provider": provider }),
                CLOUD_DEADLINE_MS,
            )
            .await?
    };
    let announce = |line: String| {
        if quiet {
            eprintln!("{line}");
        } else {
            println!("{line}");
        }
    };
    if args.device {
        let url = started["verificationUriComplete"]
            .as_str()
            .or_else(|| started["verificationUri"].as_str())
            .ok_or_else(|| anyhow!("the runtime host did not return a verification URL"))?;
        announce(format!(
            "Open {url} on any device and confirm the code {}.",
            started["userCode"].as_str().unwrap_or_default()
        ));
    } else {
        let url = started["authorizationUrl"]
            .as_str()
            .ok_or_else(|| anyhow!("the runtime host did not return a sign-in URL"))?;
        announce(format!(
            "Opening the browser to sign in. If it does not open, visit:\n{url}"
        ));
        open_in_browser(url);
    }
    wait_for_sign_in(&mut client).await
}

async fn wait_for_sign_in(client: &mut RuntimeHostRpcClient) -> Result<Value> {
    let deadline = tokio::time::Instant::now() + SIGN_IN_TIMEOUT;
    loop {
        tokio::time::sleep(Duration::from_secs(2)).await;
        let status = client.request_value("account.status", &json!({})).await?;
        if status["signInPending"] != json!(true) {
            return sign_in_result(status);
        }
        if tokio::time::Instant::now() >= deadline {
            let _ = client
                .request_value("account.signIn.cancel", &json!({}))
                .await;
            bail!("The sign-in timed out.");
        }
    }
}

/// Judges this attempt by its own outcome: an account that was already signed
/// in stays connected when a new attempt fails or is cancelled.
fn sign_in_result(status: Value) -> Result<Value> {
    match status["lastSignIn"]["ok"].as_bool() {
        Some(true) => Ok(status),
        Some(false) => bail!(
            "The sign-in did not complete: {}",
            status["lastSignIn"]["message"]
                .as_str()
                .unwrap_or("it failed or was cancelled.")
        ),
        // Only a host that predates the outcome record omits the field.
        None if status.get("lastSignIn").is_none() && status["connected"] == json!(true) => {
            Ok(status)
        }
        None => bail!("The sign-in did not complete. Run `alera account login` again."),
    }
}

fn open_in_browser(url: &str) {
    #[cfg(target_os = "macos")]
    let mut command = alera_core::child_process::windowless_async_command("open");
    #[cfg(windows)]
    let mut command = {
        let mut command = alera_core::child_process::windowless_async_command("rundll32");
        command.arg("url.dll,FileProtocolHandler");
        command
    };
    #[cfg(all(unix, not(target_os = "macos")))]
    let mut command = alera_core::child_process::windowless_async_command("xdg-open");
    // Not awaited: `xdg-open` can run the browser in the foreground, and the
    // sign-in must be polled while it is open.
    let _ = command
        .arg(url)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn();
}

fn settings_message(value: &Value) -> String {
    let access = value["access"].as_str().unwrap_or("off");
    let name = value["effectiveRuntimeName"].as_str().unwrap_or_default();
    let mut message = match access {
        "full" => format!("MCP Control is on for {name} (full control)"),
        "read" => format!("MCP Control is on for {name} (read only)"),
        _ => format!("MCP Control is off for {name}"),
    };
    if access != "off" {
        if value["accountConnected"] == json!(false) {
            message.push_str("\nSign in with `alera account login` so MCP clients can reach it.");
        } else {
            message.push_str(&format!(
                "\nAdd {} as a remote MCP server in your client.",
                mcp_endpoint()
            ));
        }
    }
    message
}

fn apps_message(value: &Value) -> String {
    let grants = value["grants"].as_array().cloned().unwrap_or_default();
    if grants.is_empty() {
        return "no MCP clients are connected".to_owned();
    }
    let mut lines = vec![format!("{} connected MCP client(s)", grants.len())];
    for grant in grants {
        let runtimes = if grant["allRuntimes"] == json!(true) {
            "all runtimes".to_owned()
        } else {
            format!(
                "{} runtime(s)",
                grant["runtimeIds"].as_array().map_or(0, Vec::len)
            )
        };
        lines.push(format!(
            "  {} | {} | {} | {}",
            grant["id"].as_str().unwrap_or_default(),
            grant["clientName"].as_str().unwrap_or_default(),
            grant["scopes"]
                .as_array()
                .map(|scopes| scopes
                    .iter()
                    .filter_map(Value::as_str)
                    .collect::<Vec<_>>()
                    .join(" "))
                .unwrap_or_default(),
            runtimes,
        ));
    }
    lines.join("\n")
}

fn tools_message() -> String {
    let tools = catalog();
    let mut lines = vec![format!("{} MCP tool(s)", tools.len())];
    for tool in tools {
        lines.push(format!(
            "  {} ({}) - {}",
            tool.name,
            tool.access.as_str(),
            tool.title
        ));
    }
    lines.join("\n")
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::sign_in_result;

    #[test]
    fn a_failed_attempt_is_a_failure_even_with_an_old_session() {
        let failed = json!({
            "connected": true,
            "signInPending": false,
            "lastSignIn": { "ok": false, "message": "cancelled" },
        });
        assert!(sign_in_result(failed).is_err());
        let done = json!({ "connected": true, "lastSignIn": { "ok": true } });
        assert!(sign_in_result(done).is_ok());
        assert!(sign_in_result(json!({ "connected": false })).is_err());
        let unknown = json!({ "connected": true, "lastSignIn": null });
        assert!(sign_in_result(unknown).is_err());
        assert!(sign_in_result(json!({ "connected": true })).is_ok());
    }
}
