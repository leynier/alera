use std::path::PathBuf;

use anyhow::Result;
use serde_json::{json, Value};

use crate::cli::{ComputerAction, ComputerAppStateArgs, ComputerCommand, ComputerPermissionsArgs};
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
    };
    match request(runtime_dir, request_type, payload).await {
        Ok(value) => report(&value, json_output, &action),
        Err(error) => {
            eprintln!("{error}");
            1
        }
    }
}

fn app_state_payload(args: &ComputerAppStateArgs) -> Value {
    json!({
        "app": args.app.app,
        "windowId": args.window_id,
        "windowIndex": args.window_index,
        "includeScreenshot": !args.no_screenshot,
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
    }
    0
}

fn render_error(value: &Value) -> String {
    let error = &value["error"];
    let code = error["code"].as_str().unwrap_or("unknown");
    let message = error["message"].as_str().unwrap_or("computer use failed");
    let mut out = format!("{code}: {message}\n");
    if let Some(steps) = error["nextSteps"].as_array() {
        for step in steps.iter().filter_map(Value::as_str) {
            out.push_str("  - ");
            out.push_str(step);
            out.push('\n');
        }
    }
    out
}

fn render_capabilities(capabilities: &Value) -> String {
    let platform = capabilities["platform"].as_str().unwrap_or("unknown");
    let provider = capabilities["provider"].as_str().unwrap_or("unknown");
    let version = capabilities["providerVersion"].as_str().unwrap_or("?");
    let supported = capabilities["supported"].as_bool().unwrap_or(false);
    let mut out = format!(
        "{} on {platform} ({provider} {version})\n",
        if supported {
            "Computer use is available"
        } else {
            "Computer use is unavailable"
        }
    );
    if let Some(reason) = capabilities["unsupportedReason"].as_str() {
        out.push_str("  Reason: ");
        out.push_str(reason);
        out.push('\n');
    }
    if supported {
        out.push_str(&render_flag_group(
            "Observation",
            &capabilities["supports"]["observation"],
        ));
        out.push_str(&render_flag_group(
            "Actions",
            &capabilities["supports"]["actions"],
        ));
    }
    out
}

fn render_flag_group(label: &str, group: &Value) -> String {
    let Some(entries) = group.as_object() else {
        return String::new();
    };
    let enabled: Vec<&str> = entries
        .iter()
        .filter(|(_, value)| value.as_bool().unwrap_or(false))
        .map(|(name, _)| name.as_str())
        .collect();
    let disabled: Vec<&str> = entries
        .iter()
        .filter(|(_, value)| !value.as_bool().unwrap_or(false))
        .map(|(name, _)| name.as_str())
        .collect();
    let mut out = format!("  {label}: {}\n", join_or_none(&enabled));
    if !disabled.is_empty() {
        out.push_str(&format!("    unavailable: {}\n", disabled.join(", ")));
    }
    out
}

fn join_or_none(values: &[&str]) -> String {
    if values.is_empty() {
        "none".to_string()
    } else {
        values.join(", ")
    }
}

fn render_permissions(permissions: &Value) -> String {
    let platform = permissions["platform"].as_str().unwrap_or("unknown");
    let mut out = format!("Computer-use permissions on {platform}\n");
    let Some(items) = permissions["items"].as_array() else {
        return out;
    };
    if items.is_empty() {
        out.push_str("  (none reported)\n");
        return out;
    }
    for item in items {
        let label = item["label"].as_str().unwrap_or("unknown");
        let id = item["id"].as_str().unwrap_or("unknown");
        let state = item["state"].as_str().unwrap_or("unknown");
        out.push_str(&format!("  {label} ({id}): {state}\n"));
        if let Some(detail) = item["detail"].as_str() {
            out.push_str(&format!("    {detail}\n"));
        }
    }
    out
}

fn render_apps(apps: &Value) -> String {
    let Some(apps) = apps.as_array() else {
        return String::new();
    };
    if apps.is_empty() {
        return "No application with a window is on the accessibility bus.\n".to_string();
    }
    let mut out = String::new();
    for app in apps {
        let name = app["name"].as_str().unwrap_or("unknown");
        let pid = app["pid"].as_u64().unwrap_or(0);
        match app["bundleId"].as_str() {
            Some(bundle_id) => out.push_str(&format!("{name} (pid {pid}, {bundle_id})\n")),
            None => out.push_str(&format!("{name} (pid {pid})\n")),
        }
    }
    out
}

fn render_windows(app: &Value, windows: &Value) -> String {
    let mut out = format!(
        "{} (pid {})\n",
        app["name"].as_str().unwrap_or("unknown"),
        app["pid"].as_u64().unwrap_or(0)
    );
    let Some(windows) = windows.as_array() else {
        return out;
    };
    if windows.is_empty() {
        out.push_str("  (no windows)\n");
        return out;
    }
    for window in windows {
        let index = window["index"].as_u64().unwrap_or(0);
        let title = window["title"].as_str().unwrap_or("");
        let active = if window["isActive"].as_bool().unwrap_or(false) {
            ", active"
        } else {
            ""
        };
        out.push_str(&format!("  index:{index} \"{title}\"{active}"));
        if let Some(bounds) = window["bounds"].as_object() {
            let number = |key: &str| bounds.get(key).and_then(Value::as_f64).unwrap_or(0.0);
            out.push_str(&format!(
                " ({}x{} @ {},{})",
                number("width"),
                number("height"),
                number("x"),
                number("y")
            ));
        }
        out.push('\n');
    }
    out
}

fn render_snapshot(snapshot: &Value) -> String {
    let mut out = format!(
        "{} (pid {})\n  Window index:{} \"{}\"\n",
        snapshot["app"]["name"].as_str().unwrap_or("unknown"),
        snapshot["app"]["pid"].as_u64().unwrap_or(0),
        snapshot["window"]["index"].as_u64().unwrap_or(0),
        snapshot["window"]["title"].as_str().unwrap_or("")
    );
    out.push_str(&format!(
        "  Elements: {}  Coordinates: {}\n",
        snapshot["elementCount"].as_u64().unwrap_or(0),
        snapshot["coordinateSpace"].as_str().unwrap_or("window")
    ));
    if let Some(index) = snapshot["focusedElementIndex"].as_u64() {
        out.push_str(&format!("  Focused element: {index}\n"));
    }
    if snapshot["truncation"]["truncated"]
        .as_bool()
        .unwrap_or(false)
    {
        out.push_str(&format!(
            "  Truncated at {} nodes\n",
            snapshot["truncation"]["maxNodes"].as_u64().unwrap_or(0)
        ));
    }
    match snapshot["screenshot"]["path"].as_str() {
        Some(path) => out.push_str(&format!(
            "  Screenshot: {path} (scale {})\n",
            snapshot["screenshot"]["scale"].as_f64().unwrap_or(1.0)
        )),
        None => {
            if let Some(error) = snapshot["screenshotError"].as_str() {
                out.push_str(&format!("  No screenshot: {error}\n"));
            }
        }
    }
    out.push('\n');
    out.push_str(snapshot["treeText"].as_str().unwrap_or(""));
    out.push('\n');
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::PermissionIdArg;

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

    #[test]
    fn the_unsupported_reason_is_rendered_for_humans() {
        let rendered = render_capabilities(&json!({
            "platform": "linux",
            "provider": "alera-computer-use-linux",
            "providerVersion": "1.0.0",
            "supported": false,
            "unsupportedReason": "no desktop session",
        }));
        assert!(rendered.contains("unavailable"));
        assert!(rendered.contains("no desktop session"));
    }

    #[test]
    fn supported_capabilities_list_what_is_and_is_not_available() {
        let rendered = render_capabilities(&json!({
            "platform": "linux",
            "provider": "p",
            "providerVersion": "1.0.0",
            "supported": true,
            "supports": {
                "observation": { "tree": true, "screenshot": false },
                "actions": { "click": true, "hotkey": false },
            },
        }));
        assert!(rendered.contains("tree"));
        assert!(rendered.contains("unavailable: screenshot"));
        assert!(rendered.contains("unavailable: hotkey"));
    }

    #[test]
    fn an_error_renders_its_recovery_steps() {
        let rendered = render_error(&json!({
            "error": {
                "code": "permission_denied",
                "message": "accessibility is not granted",
                "nextSteps": ["Run permissions", "Grant it"],
            },
        }));
        assert!(rendered.contains("permission_denied"));
        assert!(rendered.contains("- Run permissions"));
        assert!(rendered.contains("- Grant it"));
    }

    #[test]
    fn permissions_render_each_grant_with_its_state() {
        let rendered = render_permissions(&json!({
            "platform": "macos",
            "items": [
                { "id": "accessibility", "label": "Accessibility", "state": "granted" },
                {
                    "id": "screenshots",
                    "label": "Screen Recording",
                    "state": "denied",
                    "detail": "grant it in System Settings",
                },
            ],
        }));
        assert!(rendered.contains("Accessibility (accessibility): granted"));
        assert!(rendered.contains("Screen Recording (screenshots): denied"));
        assert!(rendered.contains("grant it in System Settings"));
    }
}
