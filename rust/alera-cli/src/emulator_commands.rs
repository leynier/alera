use std::io::Read;
use std::path::PathBuf;

use anyhow::{anyhow, Result};
use serde_json::{json, Map, Value};

use crate::cli::{
    EmulatorAction, EmulatorCommand, EmulatorGestureArgs, EmulatorLogcatArgs,
    EmulatorObservedActionArgs, EmulatorOptionalTargetArgs, EmulatorTargetArgs,
};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::RUNTIME_HOST_MOBILE_EMULATOR_CAPABILITY;

pub async fn run(command: EmulatorCommand) -> i32 {
    let runtime_dir = crate::runtime_dir(&command.runtime);
    let json_output = command.output.json;
    let action = command.action;
    let request = match request_for(&action) {
        Ok(request) => request,
        Err(error) => {
            eprintln!("{error}");
            return 64;
        }
    };
    match request_host(runtime_dir, request.0, request.1).await {
        Ok(value) => report(value, json_output),
        Err(error) => {
            eprintln!("{error}");
            1
        }
    }
}

fn request_for(action: &EmulatorAction) -> Result<(&'static str, Value)> {
    match action {
        EmulatorAction::Capabilities => Ok(("emulator.capabilities", json!({}))),
        EmulatorAction::Devices(args) => Ok((
            "emulator.devices",
            json!({ "platform": args.platform.map(|value| value.as_wire()) }),
        )),
        EmulatorAction::List(args) => Ok(("emulator.list", optional_target_payload(args))),
        EmulatorAction::Attach(args) => Ok((
            "emulator.attach",
            with_target(
                &args.target,
                json!({
                    "platform": args.platform.as_wire(),
                    "deviceId": required_text(&args.device_id, "device-id")?,
                }),
            )?,
        )),
        EmulatorAction::Snapshot(args) => Ok((
            "emulator.snapshot",
            with_target(
                &args.target,
                json!({ "includeScreenshot": !args.no_screenshot }),
            )?,
        )),
        EmulatorAction::Tap(args) => Ok((
            "emulator.tap",
            with_observation(&args.observed, json!({ "x": args.x, "y": args.y }))?,
        )),
        EmulatorAction::Gesture(args) => Ok(("emulator.gesture", gesture_payload(args)?)),
        EmulatorAction::Type(args) => Ok((
            "emulator.type",
            with_observation(
                &args.observed,
                json!({ "text": input_text(args.text.as_deref(), args.text_stdin)? }),
            )?,
        )),
        EmulatorAction::Button(args) => Ok((
            "emulator.button",
            with_observation(&args.observed, json!({ "button": args.button.as_wire() }))?,
        )),
        EmulatorAction::Rotate(args) => Ok((
            "emulator.rotate",
            with_observation(
                &args.observed,
                json!({ "orientation": args.orientation.as_wire() }),
            )?,
        )),
        EmulatorAction::Install(args) => Ok((
            "emulator.install",
            with_target(
                &args.target,
                json!({ "path": required_text(&args.path, "path")? }),
            )?,
        )),
        EmulatorAction::Launch(args) => Ok((
            "emulator.launch",
            with_target(
                &args.target,
                json!({
                    "bundleId": required_text(&args.bundle_id, "bundle-id")?,
                    "activity": args.activity,
                }),
            )?,
        )),
        EmulatorAction::Permission(args) => Ok((
            "emulator.permission",
            with_target(
                &args.target,
                json!({
                    "bundleId": required_text(&args.bundle_id, "bundle-id")?,
                    "permission": required_text(&args.permission, "permission")?,
                    "operation": args.operation.as_wire(),
                }),
            )?,
        )),
        EmulatorAction::Logcat(args) => Ok(("emulator.logcat", logcat_payload(args)?)),
        EmulatorAction::Detach(args) => Ok(("emulator.detach", with_target(args, json!({}))?)),
        EmulatorAction::Shutdown(args) => Ok(("emulator.shutdown", with_target(args, json!({}))?)),
    }
}

fn optional_target_payload(args: &EmulatorOptionalTargetArgs) -> Value {
    let mut payload = Map::new();
    if let Some((key, value)) = resolve_target(&args.target) {
        payload.insert(key.to_string(), Value::String(value));
    }
    Value::Object(payload)
}

fn with_target(target: &EmulatorTargetArgs, mut payload: Value) -> Result<Value> {
    let (key, value) = resolve_target(target).ok_or_else(|| {
        anyhow!(
            "--tab-id or --workspace-id is required, or run inside an Alera terminal where ALERA_WORKSPACE_ID is set."
        )
    })?;
    payload
        .as_object_mut()
        .expect("emulator payload is an object")
        .insert(key.to_string(), Value::String(value));
    Ok(payload)
}

fn with_observation(args: &EmulatorObservedActionArgs, mut payload: Value) -> Result<Value> {
    let snapshot_id = required_text(&args.snapshot_id, "snapshot-id")?;
    payload
        .as_object_mut()
        .expect("emulator action payload is an object")
        .insert("snapshotId".to_string(), Value::String(snapshot_id));
    with_target(&args.target, payload)
}

fn gesture_payload(args: &EmulatorGestureArgs) -> Result<Value> {
    with_observation(
        &args.observed,
        json!({
            "from": { "x": args.from_x, "y": args.from_y },
            "to": { "x": args.to_x, "y": args.to_y },
            "durationMs": args.duration_ms,
        }),
    )
}

fn logcat_payload(args: &EmulatorLogcatArgs) -> Result<Value> {
    with_target(
        &args.target,
        json!({
            "maxLines": args.max_lines,
            "tags": args.tag,
            "level": args.level.map(|value| value.as_wire()),
            "contains": args.contains,
            "since": args.since,
        }),
    )
}

fn resolve_target(target: &EmulatorTargetArgs) -> Option<(&'static str, String)> {
    let workspace_from_environment = std::env::var("ALERA_WORKSPACE_ID").ok();
    resolve_target_with_workspace_environment(target, workspace_from_environment.as_deref())
}

fn resolve_target_with_workspace_environment(
    target: &EmulatorTargetArgs,
    workspace_from_environment: Option<&str>,
) -> Option<(&'static str, String)> {
    non_blank(target.tab_id.as_deref())
        .map(|value| ("tabId", value))
        .or_else(|| non_blank(target.workspace_id.as_deref()).map(|value| ("workspaceId", value)))
        .or_else(|| non_blank(workspace_from_environment).map(|value| ("workspaceId", value)))
}

fn required_text(value: &str, name: &str) -> Result<String> {
    non_blank(Some(value)).ok_or_else(|| anyhow!("--{name} must not be blank."))
}

fn non_blank(value: Option<&str>) -> Option<String> {
    value
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

fn input_text(inline: Option<&str>, stdin: bool) -> Result<String> {
    if stdin {
        let mut buffer = String::new();
        std::io::stdin().read_to_string(&mut buffer)?;
        return Ok(buffer);
    }
    inline
        .map(str::to_string)
        .ok_or_else(|| anyhow!("type needs either --text <text> or --text-stdin."))
}

async fn request_host(runtime_dir: PathBuf, request_type: &str, payload: Value) -> Result<Value> {
    let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
        &runtime_dir,
        RUNTIME_HOST_MOBILE_EMULATOR_CAPABILITY,
    )
    .await?;
    client.request_value(request_type, &payload).await
}

fn report(value: Value, json_output: bool) -> i32 {
    let safe = redact_transport_credentials(value);
    let ok = safe.get("ok").and_then(Value::as_bool).unwrap_or(false);
    if json_output || ok {
        println!(
            "{}",
            serde_json::to_string_pretty(&safe).unwrap_or_else(|_| "{}".to_string())
        );
    } else {
        let error = &safe["error"];
        eprintln!(
            "{}: {}",
            error["code"].as_str().unwrap_or("emulator_error"),
            error["message"]
                .as_str()
                .unwrap_or("mobile emulator operation failed")
        );
        if let Some(steps) = error["nextSteps"].as_array() {
            for step in steps.iter().filter_map(Value::as_str) {
                eprintln!("  - {step}");
            }
        }
    }
    i32::from(!ok)
}

fn redact_transport_credentials(value: Value) -> Value {
    match value {
        Value::Array(values) => Value::Array(
            values
                .into_iter()
                .map(redact_transport_credentials)
                .collect(),
        ),
        Value::Object(values) => Value::Object(
            values
                .into_iter()
                .filter(|(key, _)| {
                    let key = key.to_ascii_lowercase();
                    !key.contains("token") && !key.contains("url")
                })
                .map(|(key, value)| (key, redact_transport_credentials(value)))
                .collect(),
        ),
        value => value,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::{EmulatorButtonArg, EmulatorButtonArgs, EmulatorObservedActionArgs};

    fn target(tab: Option<&str>, workspace: Option<&str>) -> EmulatorTargetArgs {
        EmulatorTargetArgs {
            tab_id: tab.map(str::to_string),
            workspace_id: workspace.map(str::to_string),
        }
    }

    #[test]
    fn an_explicit_tab_wins_over_an_explicit_workspace() {
        let payload = with_target(&target(Some("tab-1"), Some("workspace-1")), json!({})).unwrap();
        assert_eq!(payload, json!({ "tabId": "tab-1" }));
    }

    #[test]
    fn the_workspace_environment_is_used_only_after_explicit_targets() {
        assert_eq!(
            resolve_target_with_workspace_environment(
                &target(None, None),
                Some("workspace-from-environment"),
            ),
            Some(("workspaceId", "workspace-from-environment".to_string()))
        );
        assert_eq!(
            resolve_target_with_workspace_environment(
                &target(Some("tab-1"), None),
                Some("workspace-from-environment"),
            ),
            Some(("tabId", "tab-1".to_string()))
        );
    }

    #[test]
    fn actions_carry_the_snapshot_and_resolved_target() {
        let payload = request_for(&EmulatorAction::Button(EmulatorButtonArgs {
            observed: EmulatorObservedActionArgs {
                target: target(Some("tab-1"), None),
                snapshot_id: "snapshot-1".to_string(),
            },
            button: EmulatorButtonArg::Home,
        }))
        .unwrap()
        .1;
        assert_eq!(
            payload,
            json!({
                "tabId": "tab-1",
                "snapshotId": "snapshot-1",
                "button": "home",
            })
        );
    }

    #[test]
    fn transport_credentials_are_removed_recursively() {
        let safe = redact_transport_credentials(json!({
            "ok": true,
            "stream": {
                "url": "http://127.0.0.1:1",
                "streamToken": "secret",
                "codec": "h264",
            },
            "items": [{ "controlUrl": "ws://127.0.0.1:2", "id": "one" }],
        }));
        assert_eq!(
            safe,
            json!({
                "ok": true,
                "stream": { "codec": "h264" },
                "items": [{ "id": "one" }],
            })
        );
    }

    #[test]
    fn an_application_failure_returns_non_zero() {
        assert_eq!(
            report(
                json!({
                    "ok": false,
                    "error": {
                        "code": "unsupported_capability",
                        "message": "logcat is Android-only",
                        "nextSteps": ["Use an Android emulator."],
                    },
                }),
                true,
            ),
            1
        );
    }
}
