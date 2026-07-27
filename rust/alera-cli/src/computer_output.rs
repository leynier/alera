//! Human-readable rendering of computer-use replies.
//!
//! Kept apart from the command wiring because these are presentation rules that
//! grow with every verb, and the agent-facing contract is the JSON rather than
//! this text.

use serde_json::Value;

pub(crate) fn render_action(action: &Value) -> String {
    let path = action["path"].as_str().unwrap_or("unknown");
    let name = action["actionName"].as_str().unwrap_or("action");
    let mut out = format!("{name} invoked via {path}\n");
    if let Some(reason) = action["fallbackReason"].as_str() {
        out.push_str(&format!("  Fell back because: {reason}\n"));
    }
    // Stated plainly: an agent that reads "unverified" as "done" builds its next
    // step on something that may not have happened.
    match action["verification"]["state"].as_str() {
        Some("verified") => out.push_str(&format!(
            "  Verified: {} is now \"{}\"\n",
            action["verification"]["property"]
                .as_str()
                .unwrap_or("value"),
            action["verification"]["expected"].as_str().unwrap_or("")
        )),
        _ => out.push_str(&format!(
            "  Not verified ({}): inspect the state below before assuming it worked\n",
            action["verification"]["reason"]
                .as_str()
                .unwrap_or("unknown")
        )),
    }
    match action.get("snapshot") {
        Some(snapshot) if !snapshot.is_null() => {
            out.push('\n');
            out.push_str(&render_snapshot(snapshot));
        }
        _ => out.push_str("  The window is gone, so there is no state to report.\n"),
    }
    out
}

pub(crate) fn render_error(value: &Value) -> String {
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

pub(crate) fn render_capabilities(capabilities: &Value) -> String {
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

pub(crate) fn render_flag_group(label: &str, group: &Value) -> String {
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

pub(crate) fn render_permissions(permissions: &Value) -> String {
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

pub(crate) fn render_apps(apps: &Value) -> String {
    let Some(apps) = apps.as_array() else {
        return String::new();
    };
    if apps.is_empty() {
        return "No application with a window was found on this desktop.\n".to_string();
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

pub(crate) fn render_windows(app: &Value, windows: &Value) -> String {
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

pub(crate) fn render_snapshot(snapshot: &Value) -> String {
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
    use serde_json::json;

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
