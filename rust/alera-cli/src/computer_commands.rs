use std::path::PathBuf;

use anyhow::Result;
use serde_json::{json, Value};

use crate::cli::{
    ComputerAction, ComputerAppStateArgs, ComputerCommand, ComputerElementArgs,
    ComputerPermissionsArgs,
};
use crate::computer_output::{
    render_action, render_apps, render_capabilities, render_error, render_permissions,
    render_snapshot, render_windows,
};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::RUNTIME_HOST_COMPUTER_USE_CAPABILITY;

pub async fn run(command: ComputerCommand) -> i32 {
    let runtime_dir = crate::runtime_dir(&command.runtime);
    let json_output = command.output.json;
    let action = command.action;
    let (request_type, payload) = match &action {
        ComputerAction::Capabilities => ("computer.capabilities", json!({})),
        ComputerAction::Permissions(args) => ("computer.permissions", permissions_payload(args)),
        ComputerAction::ListApps => ("computer.listApps", json!({})),
        ComputerAction::ListWindows(args) => ("computer.listWindows", json!({ "app": args.app })),
        ComputerAction::GetAppState(args) => ("computer.getAppState", app_state_payload(args)),
        ComputerAction::Click(args) => (
            "computer.act",
            element_payload(args, json!({ "action": "click" })),
        ),
        ComputerAction::SetValue(args) => match set_value_text(args) {
            Ok(value) => (
                "computer.act",
                element_payload(
                    &args.element,
                    json!({ "action": "setValue", "value": value }),
                ),
            ),
            Err(error) => {
                eprintln!("{error}");
                return 1;
            }
        },
        ComputerAction::PerformSecondaryAction(args) => (
            "computer.act",
            element_payload(
                &args.element,
                json!({ "action": "performAction", "actionName": args.action }),
            ),
        ),
    };
    match request(runtime_dir, request_type, payload).await {
        Ok(value) => report(&value, json_output, &action),
        Err(error) => {
            eprintln!("{error}");
            1
        }
    }
}

/// Merge the element selectors into an action payload.
fn element_payload(args: &ComputerElementArgs, mut base: Value) -> Value {
    let object = base.as_object_mut().expect("action payload is an object");
    object.insert("app".to_string(), json!(args.app.app));
    object.insert("elementIndex".to_string(), json!(args.element_index));
    object.insert("snapshotId".to_string(), json!(args.snapshot_id));
    object.insert("includeScreenshot".to_string(), json!(!args.no_screenshot));
    object.insert("namespace".to_string(), json!(caller_namespace()));
    base
}

/// Which caller's observations this command's element index belongs to.
///
/// Taken from the terminal identity the runtime host already exports, so two
/// agents in different workspaces cannot resolve indexes against each other's
/// reads without either of them having to pass a flag.
fn caller_namespace() -> String {
    for name in ["ALERA_TAB_ID", "ALERA_WORKSPACE_ID"] {
        if let Ok(value) = std::env::var(name) {
            if !value.trim().is_empty() {
                return value.trim().to_string();
            }
        }
    }
    "unscoped".to_string()
}

/// Sensitive text is read from stdin so it never reaches shell history.
fn set_value_text(args: &crate::cli::ComputerSetValueArgs) -> Result<String> {
    if args.value_stdin {
        let mut buffer = String::new();
        std::io::Read::read_to_string(&mut std::io::stdin(), &mut buffer)?;
        return Ok(buffer);
    }
    args.value
        .clone()
        .ok_or_else(|| anyhow::anyhow!("set-value needs either --value <text> or --value-stdin."))
}

fn app_state_payload(args: &ComputerAppStateArgs) -> Value {
    json!({
        "app": args.app.app,
        "windowId": args.window_id,
        "windowIndex": args.window_index,
        "includeScreenshot": !args.no_screenshot,
        // The read and the action that follows it must agree on the namespace, or
        // the action cannot find the indexes the read just handed out.
        "namespace": caller_namespace(),
    })
}

fn permissions_payload(args: &ComputerPermissionsArgs) -> Value {
    match args.id {
        Some(id) => json!({ "id": id.as_wire() }),
        None => json!({}),
    }
}

/// The desktop is driven by the runtime host, never by this process.
///
/// The host is the one that lives in the user's graphical session, so it is the
/// process the operating system knows: a CLI run from a terminal would ask that
/// terminal for the accessibility grant instead.
async fn request(runtime_dir: PathBuf, request_type: &str, payload: Value) -> Result<Value> {
    let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
        &runtime_dir,
        RUNTIME_HOST_COMPUTER_USE_CAPABILITY,
    )
    .await?;
    client.request_value(request_type, &payload).await
}

/// Print the outcome and pick the exit code.
///
/// A computer-use failure exits non-zero even though the host answered
/// successfully, so a shell or an agent loop can branch on it without parsing
/// the payload. The JSON is still printed, because that is where the error code
/// and its recovery steps live.
fn report(value: &Value, json_output: bool, action: &ComputerAction) -> i32 {
    let ok = value.get("ok").and_then(Value::as_bool).unwrap_or(false);
    if json_output {
        println!(
            "{}",
            serde_json::to_string_pretty(value).unwrap_or_else(|_| "{}".to_string())
        );
        return i32::from(!ok);
    }
    if !ok {
        eprint!("{}", render_error(value));
        return 1;
    }
    match action {
        ComputerAction::Capabilities => print!("{}", render_capabilities(&value["capabilities"])),
        ComputerAction::Permissions(_) => print!("{}", render_permissions(&value["permissions"])),
        ComputerAction::ListApps => print!("{}", render_apps(&value["apps"])),
        ComputerAction::ListWindows(_) => {
            print!("{}", render_windows(&value["app"], &value["windows"]))
        }
        ComputerAction::GetAppState(_) => print!("{}", render_snapshot(&value["snapshot"])),
        ComputerAction::Click(_)
        | ComputerAction::SetValue(_)
        | ComputerAction::PerformSecondaryAction(_) => {
            print!("{}", render_action(&value["action"]))
        }
    }
    0
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::{ComputerAppArgs, PermissionIdArg};

    fn element_args() -> ComputerElementArgs {
        ComputerElementArgs {
            app: ComputerAppArgs {
                app: "krunner".to_string(),
            },
            element_index: 3,
            snapshot_id: None,
            no_screenshot: true,
        }
    }

    /// Found end to end: the read stored its observation under one namespace
    /// while the action looked under another, so every action reported a stale
    /// index. Both payloads have to carry the same value.
    #[test]
    fn a_read_and_an_action_agree_on_the_namespace() {
        let read = app_state_payload(&ComputerAppStateArgs {
            app: ComputerAppArgs {
                app: "krunner".to_string(),
            },
            window_id: None,
            window_index: None,
            no_screenshot: true,
        });
        let action = element_payload(&element_args(), json!({ "action": "click" }));
        assert_eq!(read["namespace"], action["namespace"]);
        assert!(read["namespace"].as_str().is_some_and(|v| !v.is_empty()));
    }

    #[test]
    fn an_action_payload_carries_the_element_and_its_app() {
        let payload = element_payload(&element_args(), json!({ "action": "click" }));
        assert_eq!(payload["action"], "click");
        assert_eq!(payload["app"], "krunner");
        assert_eq!(payload["elementIndex"], 3);
        assert_eq!(payload["includeScreenshot"], false);
    }

    #[test]
    fn an_absent_permission_id_sends_no_filter() {
        let payload = permissions_payload(&ComputerPermissionsArgs { id: None });
        assert_eq!(payload, json!({}));
    }

    #[test]
    fn a_permission_id_travels_as_its_wire_name() {
        let payload = permissions_payload(&ComputerPermissionsArgs {
            id: Some(PermissionIdArg::Screenshots),
        });
        assert_eq!(payload, json!({ "id": "screenshots" }));
    }

    /// An agent loop branches on the exit code, so a refusal the host reported
    /// successfully must still exit non-zero.
    #[test]
    fn a_computer_use_failure_exits_non_zero_in_both_output_modes() {
        let value = json!({
            "ok": false,
            "error": { "code": "app_blocked", "message": "no", "nextSteps": ["stop"] },
        });
        assert_eq!(report(&value, true, &ComputerAction::Capabilities), 1);
        assert_eq!(report(&value, false, &ComputerAction::Capabilities), 1);
    }

    #[test]
    fn a_successful_call_exits_zero() {
        let value = json!({
            "ok": true,
            "capabilities": {
                "platform": "linux",
                "provider": "alera-computer-use-linux",
                "providerVersion": "1.0.0",
                "supported": false,
                "unsupportedReason": "no desktop session",
            },
        });
        assert_eq!(report(&value, true, &ComputerAction::Capabilities), 0);
    }

    /// A malformed response must not read as success, or a client bug would look
    /// like a working desktop.
    #[test]
    fn a_response_without_an_ok_flag_is_treated_as_failure() {
        assert_eq!(report(&json!({}), true, &ComputerAction::Capabilities), 1);
    }
}
