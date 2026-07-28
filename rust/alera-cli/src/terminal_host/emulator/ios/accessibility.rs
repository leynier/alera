use std::time::Duration;

use serde_json::{json, Map, Value};

use super::super::accessibility::{
    bounded_string, bounded_tree_value, mark_truncated, MAX_AX_DEPTH, MAX_AX_INPUT_BYTES,
    MAX_AX_NODES, REDACTED_VALUE,
};
use super::super::contract::{EmulatorFailure, EmulatorResult};
use super::{helper_runtime::helper_failure, http_body};

const AX_REQUEST_TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Clone, Copy)]
struct Frame {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
}

pub async fn request_tree(url: &str) -> EmulatorResult<Value> {
    let response =
        http_body::get_bounded(url, AX_REQUEST_TIMEOUT, MAX_AX_INPUT_BYTES, "accessibility")
            .await?;
    if !response.status.is_success() {
        let retry = if response.status == reqwest::StatusCode::SERVICE_UNAVAILABLE {
            " Accessibility may still be warming up; retry."
        } else {
            ""
        };
        return Err(helper_failure(format!(
            "serve-sim AX returned HTTP {}.{retry}",
            response.status
        )));
    }
    let raw: Value = serde_json::from_slice(&response.bytes)
        .map_err(|error| invalid_tree(format!("serve-sim AX returned invalid JSON: {error}")))?;
    let roots = raw
        .as_array()
        .ok_or_else(|| invalid_tree("serve-sim AX root was not an array"))?;
    normalize_tree(roots)
}

fn normalize_tree(raw_roots: &[Value]) -> EmulatorResult<Value> {
    let screen = screen_frame(raw_roots);
    let mut remaining = MAX_AX_NODES;
    let mut roots = Vec::new();
    for raw in raw_roots {
        if remaining == 0 {
            if let Some(last) = roots.last_mut() {
                mark_truncated(last);
            }
            break;
        }
        roots.push(normalize_node(raw, screen, 0, false, &mut remaining));
    }
    bounded_tree_value(roots)
}

fn normalize_node(
    raw: &Value,
    screen: Frame,
    depth: usize,
    parent_sensitive: bool,
    remaining: &mut usize,
) -> Value {
    *remaining = remaining.saturating_sub(1);
    let object = raw.as_object();
    let sensitive = parent_sensitive || object.is_some_and(node_is_sensitive);
    let raw_children = object
        .and_then(|node| node.get("children"))
        .and_then(Value::as_array)
        .map(Vec::as_slice)
        .unwrap_or_default();
    let mut children = Vec::new();
    let mut truncated = false;
    if depth + 1 >= MAX_AX_DEPTH && !raw_children.is_empty() {
        truncated = true;
    } else {
        for child in raw_children {
            if *remaining == 0 {
                truncated = true;
                break;
            }
            children.push(normalize_node(
                child,
                screen,
                depth + 1,
                sensitive,
                remaining,
            ));
        }
    }
    let frame = read_frame(object.and_then(|node| node.get("frame")));
    let mut normalized = Map::from_iter([
        (
            "role".to_string(),
            Value::String(read_string(object, "role_description")),
        ),
        (
            "type".to_string(),
            Value::String(read_string(object, "type")),
        ),
        (
            "label".to_string(),
            Value::String(if sensitive {
                REDACTED_VALUE.to_string()
            } else {
                read_string(object, "AXLabel")
            }),
        ),
        (
            "value".to_string(),
            Value::String(if sensitive {
                REDACTED_VALUE.to_string()
            } else {
                read_string(object, "AXValue")
            }),
        ),
        (
            "enabled".to_string(),
            Value::Bool(
                object
                    .and_then(|node| node.get("enabled"))
                    .and_then(Value::as_bool)
                    != Some(false),
            ),
        ),
        ("frame".to_string(), normalized_frame(frame, screen)),
        ("children".to_string(), Value::Array(children)),
    ]);
    let id = read_string(object, "AXUniqueId");
    if !sensitive && !id.is_empty() {
        normalized.insert("id".to_string(), Value::String(id));
    }
    if sensitive {
        normalized.insert("secure".to_string(), Value::Bool(true));
    }
    if truncated {
        normalized.insert("truncated".to_string(), Value::Bool(true));
    }
    Value::Object(normalized)
}

fn node_is_sensitive(node: &Map<String, Value>) -> bool {
    for key in [
        "password",
        "secure",
        "isPassword",
        "isSecure",
        "isSecureTextEntry",
        "AXProtectedContent",
    ] {
        if node.get(key).and_then(Value::as_bool) == Some(true) {
            return true;
        }
    }
    ["type", "role_description", "AXRole", "AXSubrole"]
        .iter()
        .filter_map(|key| node.get(*key).and_then(Value::as_str))
        .any(role_marks_sensitive)
        || is_text_input(node)
            && ["AXLabel", "AXUniqueId", "identifier", "placeholder"]
                .iter()
                .filter_map(|key| node.get(*key).and_then(Value::as_str))
                .any(label_marks_sensitive)
}

fn role_marks_sensitive(value: &str) -> bool {
    let compact = value
        .chars()
        .filter(|character| character.is_ascii_alphanumeric())
        .flat_map(char::to_lowercase)
        .collect::<String>();
    compact.contains("securetextfield") || compact.contains("passwordfield")
}

fn is_text_input(node: &Map<String, Value>) -> bool {
    ["type", "role_description", "AXRole", "AXSubrole"]
        .iter()
        .filter_map(|key| node.get(*key).and_then(Value::as_str))
        .any(|value| {
            let compact = value
                .chars()
                .filter(|character| character.is_ascii_alphanumeric())
                .flat_map(char::to_lowercase)
                .collect::<String>();
            compact.contains("textfield") || compact.contains("textarea")
        })
}

fn label_marks_sensitive(value: &str) -> bool {
    let compact = value
        .chars()
        .filter(|character| character.is_ascii_alphanumeric())
        .flat_map(char::to_lowercase)
        .collect::<String>();
    [
        "password",
        "passcode",
        "pinentry",
        "onetimecode",
        "otp",
        "securitycode",
        "secret",
        "token",
        "cvv",
    ]
    .iter()
    .any(|keyword| compact.contains(keyword))
}

fn read_string(object: Option<&Map<String, Value>>, key: &str) -> String {
    object
        .and_then(|node| node.get(key))
        .and_then(Value::as_str)
        .map(bounded_string)
        .unwrap_or_default()
}

fn read_frame(value: Option<&Value>) -> Frame {
    let object = value.and_then(Value::as_object);
    Frame {
        x: finite_number(object.and_then(|frame| frame.get("x"))),
        y: finite_number(object.and_then(|frame| frame.get("y"))),
        width: finite_number(object.and_then(|frame| frame.get("width"))),
        height: finite_number(object.and_then(|frame| frame.get("height"))),
    }
}

fn finite_number(value: Option<&Value>) -> f64 {
    value
        .and_then(Value::as_f64)
        .filter(|value| value.is_finite())
        .unwrap_or(0.0)
}

fn screen_frame(roots: &[Value]) -> Frame {
    let frame = read_frame(
        roots
            .first()
            .and_then(Value::as_object)
            .and_then(|root| root.get("frame")),
    );
    if frame.width > 0.0 && frame.height > 0.0 {
        frame
    } else {
        Frame {
            x: 0.0,
            y: 0.0,
            width: 1.0,
            height: 1.0,
        }
    }
}

fn normalized_frame(frame: Frame, screen: Frame) -> Value {
    json!({
        "x": round4((frame.x - screen.x) / screen.width),
        "y": round4((frame.y - screen.y) / screen.height),
        "width": round4(frame.width / screen.width),
        "height": round4(frame.height / screen.height),
    })
}

fn round4(value: f64) -> f64 {
    (value * 10_000.0).round() / 10_000.0
}

fn invalid_tree(message: impl Into<String>) -> EmulatorFailure {
    EmulatorFailure::new(
        "provider_incompatible",
        message,
        ["Restart the iOS Simulator and retry the snapshot."],
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::terminal_host::emulator::accessibility::MAX_AX_OUTPUT_BYTES;

    #[test]
    fn normalizes_frames_and_redacts_secure_values() {
        let raw = json!([{
            "type": "Application",
            "role_description": "application",
            "frame": {"x": 10, "y": 20, "width": 200, "height": 400},
            "children": [{
                "type": "SecureTextField",
                "role_description": "secure text field",
                "AXLabel": "Password",
                "AXValue": "hunter2",
                "AXUniqueId": "password",
                "frame": {"x": 60, "y": 120, "width": 100, "height": 40},
                "children": []
            }]
        }]);
        let tree = normalize_tree(raw.as_array().unwrap()).unwrap();
        let secure = &tree[0]["children"][0];
        assert_eq!(secure["label"], REDACTED_VALUE);
        assert_eq!(secure["value"], REDACTED_VALUE);
        assert_eq!(secure["secure"], true);
        assert_eq!(secure["frame"]["x"], 0.25);
        assert_eq!(secure["frame"]["y"], 0.25);
        assert!(!serde_json::to_string(&tree).unwrap().contains("hunter2"));
    }

    #[test]
    fn a_button_named_password_is_not_treated_as_secret() {
        let raw = json!([{
            "type": "Button",
            "role_description": "button",
            "AXLabel": "Password",
            "AXValue": "show",
            "frame": {"x": 0, "y": 0, "width": 1, "height": 1},
            "children": []
        }]);
        let tree = normalize_tree(raw.as_array().unwrap()).unwrap();
        assert_eq!(tree[0]["value"], "show");
        assert!(tree[0].get("secure").is_none());
    }

    #[test]
    fn redacts_unflagged_password_text_fields_and_their_identifiers() {
        let raw = json!([{
            "type": "TextField",
            "AXUniqueId": "password_input",
            "AXValue": "hunter2",
            "frame": {"x": 0, "y": 0, "width": 1, "height": 1},
            "children": []
        }]);
        let tree = normalize_tree(raw.as_array().unwrap()).unwrap();
        assert_eq!(tree[0]["value"], REDACTED_VALUE);
        assert!(tree[0].get("id").is_none());
        assert!(!serde_json::to_string(&tree).unwrap().contains("hunter2"));
    }

    #[test]
    fn caps_depth_nodes_and_serialized_bytes() {
        let mut nested = json!({
            "type": "StaticText",
            "AXLabel": "x".repeat(2048),
            "children": []
        });
        for _ in 0..MAX_AX_DEPTH + 10 {
            nested = json!({"type": "Group", "children": [nested]});
        }
        let roots = (0..MAX_AX_NODES + 20)
            .map(|_| nested.clone())
            .collect::<Vec<_>>();
        let tree = normalize_tree(&roots).unwrap();
        let encoded = serde_json::to_vec_pretty(&tree).unwrap();
        assert!(encoded.len() <= MAX_AX_OUTPUT_BYTES);
        assert!(count_nodes(&tree) <= MAX_AX_NODES);
        assert!(maximum_depth(&tree) <= MAX_AX_DEPTH);
        assert!(encoded
            .windows(b"truncated".len())
            .any(|part| part == b"truncated"));
    }

    fn count_nodes(value: &Value) -> usize {
        value
            .as_array()
            .map(|nodes| {
                nodes
                    .iter()
                    .map(|node| 1 + count_nodes(&node["children"]))
                    .sum()
            })
            .unwrap_or(0)
    }

    fn maximum_depth(value: &Value) -> usize {
        value
            .as_array()
            .map(|nodes| {
                nodes
                    .iter()
                    .map(|node| 1 + maximum_depth(&node["children"]))
                    .max()
                    .unwrap_or(0)
            })
            .unwrap_or(0)
    }
}
