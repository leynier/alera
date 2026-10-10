//! Tab and terminal lifecycle through the runtime host: closing a tab with
//! its session, renaming, AI titles, restart, terminate, and Terminal Pulse.

use anyhow::{bail, Result};
use serde_json::{json, Value};

use crate::agent_profile_commands::ensure_capabilities;
use crate::cli::{
    RuntimeDirArgs, TabAction, TerminalAction, TerminalPulseAction, TerminalPulseSetArgs,
};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::ai_assist_capabilities::RUNTIME_HOST_AI_ASSIST_AGENT_TITLE_CAPABILITY;
use crate::terminal_host::protocol::RUNTIME_HOST_MOBILE_TAB_RENAME_CAPABILITY;
use crate::{print_error, print_value};

/// `tab remove --terminate`, `tab rename`, and `tab generate-title`.
pub(crate) async fn run_tab(runtime: &RuntimeDirArgs, action: TabAction, json_output: bool) -> i32 {
    match tab(runtime, action).await {
        Ok((value, message)) => {
            print_value(&value, json_output, message);
            0
        }
        Err(error) => print_error(error),
    }
}

async fn tab(runtime: &RuntimeDirArgs, action: TabAction) -> Result<(Value, &'static str)> {
    let mut client = RuntimeHostRpcClient::connect_or_start(&crate::runtime_dir(runtime)).await?;
    match action {
        TabAction::Remove(args) => {
            // The host ends the tab's terminal sessions when it removes it.
            client
                .request_value("tab.remove", &json!({ "id": args.id }))
                .await?;
            Ok((json!({ "id": args.id, "terminated": true }), "tab closed"))
        }
        TabAction::Rename(args) => {
            let title = args.title.trim();
            if title.is_empty() {
                bail!("--title cannot be empty");
            }
            ensure_capabilities(&mut client, &[RUNTIME_HOST_MOBILE_TAB_RENAME_CAPABILITY]).await?;
            let tab = client
                .request_value("tab.rename", &json!({ "id": args.id, "title": title }))
                .await?;
            Ok((tab, "tab renamed"))
        }
        TabAction::GenerateTitle(args) => {
            ensure_capabilities(
                &mut client,
                &[RUNTIME_HOST_AI_ASSIST_AGENT_TITLE_CAPABILITY],
            )
            .await?;
            let store = crate::open_store(runtime).await?;
            let Some(tab) = store.find_workspace_tab(&args.id).await? else {
                bail!("Workspace tab not found: {}", args.id);
            };
            let result = client
                .request_value("aiText.agentTitle.generate", &title_request(&tab))
                .await?;
            Ok((result, "tab title generated"))
        }
        _ => bail!("unsupported tab action"),
    }
}

/// The host refuses a title for a conversation that changed since the
/// caller looked, so the request names the tab's current conversation.
pub(crate) fn title_request(tab: &alera_core::runtime::WorkspaceTabRecord) -> Value {
    json!({
        "tabId": tab.id,
        "expectedConversationId": tab.payload["agentTitleConversationId"],
        "expectedRevision": tab.payload["agentTitleRevision"],
    })
}

/// `terminal restart`, `terminal terminate`, and `terminal pulse`.
pub(crate) async fn run_terminal(
    client: &mut RuntimeHostRpcClient,
    action: TerminalAction,
    json_output: bool,
) -> i32 {
    match terminal(client, action).await {
        Ok((value, message)) => {
            print_value(&value, json_output, message);
            0
        }
        Err(error) => print_error(error),
    }
}

async fn terminal(
    client: &mut RuntimeHostRpcClient,
    action: TerminalAction,
) -> Result<(Value, &'static str)> {
    match action {
        TerminalAction::Restart(args) => {
            let value = client
                .request_value(
                    "terminal.restart",
                    &json!({ "sessionId": args.handle, "headless": true }),
                )
                .await?;
            Ok((value, "terminal restarted"))
        }
        TerminalAction::Terminate(args) => {
            client
                .request_value("terminate", &json!({ "sessionId": args.handle }))
                .await?;
            Ok((
                json!({ "handle": args.handle, "terminated": true }),
                "terminal terminated",
            ))
        }
        TerminalAction::Pulse(command) => match command.action {
            TerminalPulseAction::Show(args) => {
                let status = pulse_status(client, &args.handle).await?;
                Ok((status, "terminal pulse"))
            }
            TerminalPulseAction::Set(args) => {
                let status = pulse_status(client, &args.handle).await?;
                let payload = pulse_configure_payload(&status, &args)?;
                let value = client
                    .request_value("terminal.pulse.configure", &payload)
                    .await?;
                Ok((value, "terminal pulse updated"))
            }
        },
        _ => bail!("unsupported terminal action"),
    }
}

async fn pulse_status(client: &mut RuntimeHostRpcClient, handle: &str) -> Result<Value> {
    client
        .request_value("terminal.pulse.status", &json!({ "sessionId": handle }))
        .await
}

/// The configure request: the saved configuration with the given changes,
/// armed as requested or as it already was.
pub(crate) fn pulse_configure_payload(
    status: &Value,
    args: &TerminalPulseSetArgs,
) -> Result<Value> {
    let mut configuration = status["configuration"].clone();
    if !configuration.is_object() {
        bail!("runtime host returned no Terminal Pulse configuration");
    }
    if let Some(input) = &args.input {
        if input.is_empty() {
            bail!("--input cannot be empty");
        }
        configuration["command"] = json!(input);
    }
    if let Some(enter) = args.enter {
        configuration["appendEnter"] = json!(enter);
    }
    if let Some(delay) = args.delay_ms {
        configuration["delayMs"] = json!(delay);
    }
    let armed = if args.arm {
        true
    } else if args.disarm {
        false
    } else {
        status["armed"].as_bool().unwrap_or(false)
    };
    Ok(json!({
        "sessionId": args.handle,
        "configuration": configuration,
        "armed": armed,
    }))
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::{pulse_configure_payload, title_request};
    use crate::cli::TerminalPulseSetArgs;

    fn args() -> TerminalPulseSetArgs {
        TerminalPulseSetArgs {
            handle: "term-1".into(),
            input: None,
            enter: None,
            delay_ms: None,
            arm: false,
            disarm: false,
        }
    }

    fn status(armed: bool) -> serde_json::Value {
        json!({
            "configuration": { "command": "r", "appendEnter": true, "delayMs": 2000 },
            "armed": armed,
        })
    }

    #[test]
    fn pulse_keeps_what_was_not_changed() {
        let payload = pulse_configure_payload(&status(true), &args()).unwrap();
        assert_eq!(
            payload,
            json!({
                "sessionId": "term-1",
                "configuration": { "command": "r", "appendEnter": true, "delayMs": 2000 },
                "armed": true,
            })
        );
    }

    #[test]
    fn pulse_applies_changes_and_arming() {
        let changed = TerminalPulseSetArgs {
            input: Some("npm test".into()),
            enter: Some(false),
            delay_ms: Some(500),
            arm: true,
            ..args()
        };
        let payload = pulse_configure_payload(&status(false), &changed).unwrap();
        assert_eq!(payload["configuration"]["command"], "npm test");
        assert_eq!(payload["configuration"]["appendEnter"], false);
        assert_eq!(payload["configuration"]["delayMs"], 500);
        assert_eq!(payload["armed"], true);
        let disarm = TerminalPulseSetArgs {
            disarm: true,
            ..args()
        };
        assert_eq!(
            pulse_configure_payload(&status(true), &disarm).unwrap()["armed"],
            false
        );
        let empty = TerminalPulseSetArgs {
            input: Some(String::new()),
            ..args()
        };
        assert!(pulse_configure_payload(&status(true), &empty).is_err());
    }

    #[test]
    fn title_request_names_the_current_conversation() {
        let mut tab = crate::tab_record_factory::tab_from_args(crate::cli::TabCreateArgs {
            workspace_id: "ws".into(),
            title: "Agent".into(),
            kind: "terminal".into(),
            command: None,
            spawn: false,
        })
        .unwrap();
        tab.payload["agentTitleConversationId"] = json!("conv-1");
        tab.payload["agentTitleRevision"] = json!(3);
        let request = title_request(&tab);
        assert_eq!(request["tabId"], tab.id.as_str());
        assert_eq!(request["expectedConversationId"], "conv-1");
        assert_eq!(request["expectedRevision"], 3);
        tab.payload = json!({});
        let request = title_request(&tab);
        assert!(request["expectedRevision"].is_null());
        assert!(request
            .as_object()
            .unwrap()
            .contains_key("expectedRevision"));
    }
}
