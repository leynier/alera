use alera_core::runtime::WorkspaceTabRecord;
use chrono::DateTime;
use serde::Deserialize;
use serde_json::{json, Value};

use crate::terminal_host::emulator::{
    EmulatorFailure, EmulatorPlatform, EmulatorResult, GesturePoint,
};

pub(crate) struct EmulatorRequestCompletion {
    pub(super) response: Value,
    pub(super) broadcast: Option<EmulatorBroadcast>,
    pub(super) pointer_transition: Option<PointerTransition>,
}

pub(super) enum PointerTransition {
    Began { tab_id: String, client_id: u64 },
    Ended { tab_id: String, client_id: u64 },
}

pub(super) struct EmulatorBroadcast {
    pub(super) tab_id: String,
    pub(super) workspace_id: String,
    pub(super) reason: &'static str,
    pub(super) workspace_tabs_changed: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct StoredEmulatorPayload {
    pub(super) schema_version: u32,
    pub(super) platform: EmulatorPlatform,
    pub(super) device_id: String,
}

pub(super) struct LogcatRequest {
    pub(super) max_lines: u32,
    pub(super) tags: Vec<String>,
    pub(super) level: Option<String>,
    pub(super) contains: Option<String>,
    pub(super) since_epoch: Option<String>,
}

pub(super) fn stored_payload(tab: &WorkspaceTabRecord) -> EmulatorResult<StoredEmulatorPayload> {
    let value =
        tab.payload.get("mobileEmulator").cloned().ok_or_else(|| {
            tab_failure("provider_incompatible", "Emulator tab payload is missing.")
        })?;
    let parsed: StoredEmulatorPayload = serde_json::from_value(value).map_err(|error| {
        tab_failure(
            "provider_incompatible",
            &format!("Emulator tab payload is invalid: {error}"),
        )
    })?;
    if parsed.schema_version != 1 {
        return Err(tab_failure(
            "provider_incompatible",
            "Emulator tab schema version is not supported.",
        ));
    }
    Ok(parsed)
}

pub(super) fn parked_session_value(tab: &WorkspaceTabRecord) -> EmulatorResult<Value> {
    let stored = stored_payload(tab)?;
    Ok(json!({
        "id": tab.id,
        "workspaceId": tab.workspace_id,
        "tabId": tab.id,
        "deviceId": stored.device_id,
        "platform": stored.platform,
        "state": "parked",
        "managedDevice": false,
        "stream": {
            "state": "parked",
            "codec": if stored.platform == EmulatorPlatform::Android {
                "h264"
            } else {
                "mjpeg"
            },
            "url": Value::Null,
        },
    }))
}

pub(super) fn optional_platform(payload: &Value) -> EmulatorResult<Option<EmulatorPlatform>> {
    payload
        .get("platform")
        .filter(|value| !value.is_null())
        .map(|value| {
            serde_json::from_value(value.clone())
                .map_err(|_| EmulatorFailure::invalid("Platform must be android or ios."))
        })
        .transpose()
}

pub(super) fn required_platform(payload: &Value) -> EmulatorResult<EmulatorPlatform> {
    optional_platform(payload)?.ok_or_else(|| EmulatorFailure::invalid("Platform is required."))
}

pub(super) fn required_string<'a>(payload: &'a Value, key: &str) -> EmulatorResult<&'a str> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| EmulatorFailure::invalid(format!("`{key}` is required.")))
}

pub(super) fn required_text(payload: &Value) -> EmulatorResult<&str> {
    const MAX_TEXT_BYTES: usize = 16 * 1024;
    let text = payload
        .get("text")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| EmulatorFailure::invalid("`text` is required."))?;
    if text.len() > MAX_TEXT_BYTES {
        return Err(EmulatorFailure::invalid(format!(
            "`text` must not exceed {MAX_TEXT_BYTES} UTF-8 bytes."
        )));
    }
    Ok(text)
}

pub(super) fn optional_string<'a>(
    payload: &'a Value,
    key: &str,
) -> EmulatorResult<Option<&'a str>> {
    match payload.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(value)) if !value.trim().is_empty() => Ok(Some(value.trim())),
        _ => Err(EmulatorFailure::invalid(format!(
            "`{key}` must be a non-empty string."
        ))),
    }
}

pub(super) fn interactive_input(payload: &Value) -> bool {
    payload.get("interactive").and_then(Value::as_bool) == Some(true)
}

pub(super) fn coordinates(payload: &Value) -> EmulatorResult<(f64, f64)> {
    let x = payload
        .get("x")
        .and_then(Value::as_f64)
        .ok_or_else(|| EmulatorFailure::invalid("`x` is required."))?;
    let y = payload
        .get("y")
        .and_then(Value::as_f64)
        .ok_or_else(|| EmulatorFailure::invalid("`y` is required."))?;
    Ok((x, y))
}

pub(super) fn gesture_points(payload: &Value) -> EmulatorResult<Vec<GesturePoint>> {
    if let Some(points) = payload.get("points") {
        let points = serde_json::from_value(points.clone())
            .map_err(|_| EmulatorFailure::invalid("Gesture points are invalid."))?;
        validate_gesture_points(points)
    } else {
        let from = payload
            .get("from")
            .ok_or_else(|| EmulatorFailure::invalid("Gesture `from` is required."))?;
        let to = payload
            .get("to")
            .ok_or_else(|| EmulatorFailure::invalid("Gesture `to` is required."))?;
        let coordinate = |value: &Value, key: &str| {
            value
                .get(key)
                .and_then(Value::as_f64)
                .ok_or_else(|| EmulatorFailure::invalid(format!("Gesture `{key}` is required.")))
        };
        validate_gesture_points(vec![
            GesturePoint {
                kind: Some("begin".into()),
                x: coordinate(from, "x")?,
                y: coordinate(from, "y")?,
                edge: None,
            },
            GesturePoint {
                kind: Some("end".into()),
                x: coordinate(to, "x")?,
                y: coordinate(to, "y")?,
                edge: None,
            },
        ])
    }
}

fn validate_gesture_points(points: Vec<GesturePoint>) -> EmulatorResult<Vec<GesturePoint>> {
    const MAX_GESTURE_POINTS: usize = 128;
    if !(2..=MAX_GESTURE_POINTS).contains(&points.len()) {
        return Err(EmulatorFailure::invalid(format!(
            "A gesture must contain between 2 and {MAX_GESTURE_POINTS} points."
        )));
    }
    for (index, point) in points.iter().enumerate() {
        let expected = if index == 0 {
            "begin"
        } else if index + 1 == points.len() {
            "end"
        } else {
            "move"
        };
        if point.kind.as_deref().is_some_and(|kind| kind != expected) {
            return Err(EmulatorFailure::invalid(
                "Gesture point types must follow begin, move, then end order.",
            ));
        }
    }
    Ok(points)
}

pub(super) fn logcat_request(payload: &Value) -> EmulatorResult<LogcatRequest> {
    let max_lines = payload
        .get("maxLines")
        .map_or(Some(200), Value::as_u64)
        .filter(|value| (1..=1000).contains(value))
        .ok_or_else(|| EmulatorFailure::invalid("`maxLines` must be between 1 and 1000."))?
        as u32;
    let tags = payload.get("tags").map_or(Ok(Vec::new()), |value| {
        value
            .as_array()
            .ok_or_else(|| EmulatorFailure::invalid("`tags` must be an array."))
            .and_then(|values| {
                if values.len() > 32 {
                    return Err(EmulatorFailure::invalid(
                        "At most 32 Android log tags may be requested.",
                    ));
                }
                values
                    .iter()
                    .map(|value| {
                        value
                            .as_str()
                            .map(str::trim)
                            .filter(|value| !value.is_empty())
                            .map(str::to_string)
                            .ok_or_else(|| {
                                EmulatorFailure::invalid(
                                    "Android log tags must be non-empty strings.",
                                )
                            })
                    })
                    .collect()
            })
    })?;
    let level = optional_string(payload, "level")?.map(str::to_string);
    if level.as_deref().is_some_and(|value| {
        !matches!(
            value,
            "verbose" | "debug" | "info" | "warn" | "error" | "fatal"
        )
    }) {
        return Err(EmulatorFailure::invalid("Unknown Android log level."));
    }
    let contains = optional_string(payload, "contains")?.map(str::to_string);
    let since_epoch = optional_string(payload, "since")?
        .map(|value| {
            let timestamp = DateTime::parse_from_rfc3339(value)
                .map_err(|_| EmulatorFailure::invalid("`since` must be an RFC 3339 timestamp."))?;
            if timestamp.timestamp() < 0 {
                return Err(EmulatorFailure::invalid(
                    "`since` must not be before the Unix epoch.",
                ));
            }
            Ok(format!(
                "{}.{:03}",
                timestamp.timestamp(),
                timestamp.timestamp_subsec_millis()
            ))
        })
        .transpose()?;
    Ok(LogcatRequest {
        max_lines,
        tags,
        level,
        contains,
        since_epoch,
    })
}

pub(super) fn filter_logcat<'a>(
    raw: &'a str,
    contains: Option<&str>,
    max_lines: usize,
) -> Vec<&'a str> {
    let mut lines: Vec<&str> = raw
        .lines()
        .filter(|line| contains.is_none_or(|needle| line.contains(needle)))
        .collect();
    if lines.len() > max_lines {
        lines.drain(..lines.len() - max_lines);
    }
    lines
}

pub(super) fn action_ok(tab_id: &str) -> Value {
    json!({"ok": true, "tabId": tab_id})
}

pub(super) fn state_failure(error: impl std::fmt::Display) -> EmulatorFailure {
    EmulatorFailure::new(
        "provider_incompatible",
        error.to_string(),
        ["Retry after refreshing the workspace state."],
    )
}

pub(super) fn tab_failure(code: &'static str, message: &str) -> EmulatorFailure {
    EmulatorFailure::new(code, message, ["Refresh the workspace tabs and retry."])
}

pub(super) fn unavailable_capabilities() -> Value {
    json!({
        "ok": true,
        "kind": "emulatorCapabilities",
        "platforms": {
            "android": {"available": false, "deviceCount": 0, "message": "Manager unavailable", "operations": []},
            "ios": {"available": false, "deviceCount": 0, "message": "Manager unavailable", "operations": []},
        },
        "coordinateSpace": "normalized",
        "origin": "topLeft",
    })
}
