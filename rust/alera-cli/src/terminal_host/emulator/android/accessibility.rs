use std::collections::HashMap;

use serde_json::{json, Map, Value};

use super::super::accessibility::{
    bounded_string, bounded_tree_text, mark_truncated, MAX_AX_DEPTH, MAX_AX_INPUT_BYTES,
    MAX_AX_NODES, REDACTED_VALUE,
};
use super::super::contract::{EmulatorFailure, EmulatorResult};

struct NodeFrame {
    node: Option<Value>,
    sensitive: bool,
}

pub fn normalize_uiautomator_tree(xml: &[u8]) -> EmulatorResult<String> {
    if xml.len() > MAX_AX_INPUT_BYTES {
        return Err(EmulatorFailure::new(
            "provider_incompatible",
            "Android accessibility returned more than 1 MiB of XML.",
            ["Simplify the visible screen and retry the snapshot."],
        ));
    }
    let xml = std::str::from_utf8(xml).map_err(|_| invalid_xml("output was not UTF-8"))?;
    let mut roots = Vec::new();
    let mut stack: Vec<NodeFrame> = Vec::new();
    let mut retained = 0usize;
    let mut dropped_root = false;
    let mut cursor = 0usize;
    while let Some(relative) = xml[cursor..].find('<') {
        let start = cursor + relative;
        let end = find_tag_end(xml, start).ok_or_else(|| invalid_xml("unterminated tag"))?;
        let tag = xml[start + 1..end].trim();
        cursor = end + 1;
        if tag.starts_with("!--") || tag.starts_with('?') || tag.starts_with('!') {
            continue;
        }
        if let Some(closing) = tag.strip_prefix('/') {
            if closing.trim() == "node" {
                finish_node(&mut stack, &mut roots)?;
            }
            continue;
        }
        let self_closing = tag.ends_with('/');
        let content = tag.trim_end_matches('/').trim_end();
        let name_end = content.find(char::is_whitespace).unwrap_or(content.len());
        if &content[..name_end] != "node" {
            continue;
        }
        let attributes = parse_attributes(&content[name_end..])?;
        let parent_retained = stack.last().is_none_or(|frame| frame.node.is_some());
        let within_depth = stack.len() < MAX_AX_DEPTH;
        let keep = parent_retained && within_depth && retained < MAX_AX_NODES;
        if !keep {
            if let Some(parent) = stack.last_mut().and_then(|frame| frame.node.as_mut()) {
                mark_truncated(parent);
            } else {
                dropped_root = true;
            }
        }
        let sensitive = stack.last().is_some_and(|frame| frame.sensitive)
            || attributes_mark_sensitive(&attributes);
        let node = keep.then(|| {
            retained += 1;
            normalized_node(&attributes, sensitive)
        });
        stack.push(NodeFrame { node, sensitive });
        if self_closing {
            finish_node(&mut stack, &mut roots)?;
        }
    }
    if !stack.is_empty() {
        return Err(invalid_xml("unclosed node"));
    }
    if roots.is_empty() {
        return Err(invalid_xml("no accessibility nodes were found"));
    }
    if dropped_root {
        if let Some(last) = roots.last_mut() {
            mark_truncated(last);
        }
    }
    bounded_tree_text(roots)
}

fn finish_node(stack: &mut Vec<NodeFrame>, roots: &mut Vec<Value>) -> EmulatorResult<()> {
    let frame = stack
        .pop()
        .ok_or_else(|| invalid_xml("unexpected closing node"))?;
    let Some(node) = frame.node else {
        return Ok(());
    };
    if let Some(parent) = stack.last_mut() {
        if let Some(parent) = parent.node.as_mut() {
            parent["children"]
                .as_array_mut()
                .expect("normalized nodes always have children")
                .push(node);
        }
    } else {
        roots.push(node);
    }
    Ok(())
}

fn normalized_node(attributes: &HashMap<String, String>, sensitive: bool) -> Value {
    let mut node = Map::new();
    copy_string(&mut node, "className", attributes.get("class"), false);
    copy_string(&mut node, "text", attributes.get("text"), sensitive);
    copy_string(
        &mut node,
        "resourceId",
        attributes.get("resource-id"),
        false,
    );
    copy_string(
        &mut node,
        "contentDescription",
        attributes.get("content-desc"),
        sensitive,
    );
    copy_string(&mut node, "packageName", attributes.get("package"), false);
    for (source, target) in [
        ("clickable", "clickable"),
        ("enabled", "enabled"),
        ("focused", "focused"),
    ] {
        if let Some(value) = attributes
            .get(source)
            .and_then(|value| match value.as_str() {
                "true" => Some(true),
                "false" => Some(false),
                _ => None,
            })
        {
            node.insert(target.to_string(), Value::Bool(value));
        }
    }
    if let Some(bounds) = attributes
        .get("bounds")
        .and_then(|value| parse_bounds(value))
    {
        node.insert("bounds".to_string(), bounds);
    }
    if sensitive {
        node.insert("secure".to_string(), Value::Bool(true));
    }
    node.insert("children".to_string(), Value::Array(Vec::new()));
    Value::Object(node)
}

fn copy_string(node: &mut Map<String, Value>, key: &str, value: Option<&String>, redact: bool) {
    let Some(value) = value.filter(|value| !value.is_empty()) else {
        return;
    };
    node.insert(
        key.to_string(),
        Value::String(if redact {
            REDACTED_VALUE.to_string()
        } else {
            bounded_string(value)
        }),
    );
}

fn attributes_mark_sensitive(attributes: &HashMap<String, String>) -> bool {
    attributes.iter().any(|(key, value)| {
        matches!(
            key.to_ascii_lowercase().as_str(),
            "password" | "secure" | "is-password" | "is-secure"
        ) && value.eq_ignore_ascii_case("true")
    }) || attributes
        .get("class")
        .is_some_and(|value| role_marks_sensitive(value))
        || attributes.get("class").is_some_and(|class_name| {
            class_name.to_ascii_lowercase().contains("edittext")
                && ["resource-id", "content-desc"]
                    .iter()
                    .filter_map(|key| attributes.get(*key))
                    .any(|value| label_marks_sensitive(value))
        })
}

fn role_marks_sensitive(value: &str) -> bool {
    let compact = value
        .chars()
        .filter(|character| character.is_ascii_alphanumeric())
        .flat_map(char::to_lowercase)
        .collect::<String>();
    compact.contains("securetextfield") || compact.contains("passwordfield")
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

fn parse_bounds(value: &str) -> Option<Value> {
    let captures = value
        .trim()
        .strip_prefix('[')?
        .strip_suffix(']')?
        .split("][")
        .collect::<Vec<_>>();
    if captures.len() != 2 {
        return None;
    }
    let parse_pair = |pair: &str| -> Option<(i64, i64)> {
        let (first, second) = pair.split_once(',')?;
        Some((first.parse().ok()?, second.parse().ok()?))
    };
    let (left, top) = parse_pair(captures[0])?;
    let (right, bottom) = parse_pair(captures[1])?;
    Some(json!({"left": left, "top": top, "right": right, "bottom": bottom}))
}

fn find_tag_end(xml: &str, start: usize) -> Option<usize> {
    let mut quote = None;
    for (offset, character) in xml[start + 1..].char_indices() {
        if matches!(character, '"' | '\'') {
            if quote == Some(character) {
                quote = None;
            } else if quote.is_none() {
                quote = Some(character);
            }
        } else if character == '>' && quote.is_none() {
            return Some(start + 1 + offset);
        }
    }
    None
}

fn parse_attributes(input: &str) -> EmulatorResult<HashMap<String, String>> {
    let bytes = input.as_bytes();
    let mut cursor = 0usize;
    let mut attributes = HashMap::new();
    while cursor < bytes.len() {
        while cursor < bytes.len() && bytes[cursor].is_ascii_whitespace() {
            cursor += 1;
        }
        if cursor >= bytes.len() {
            break;
        }
        let name_start = cursor;
        while cursor < bytes.len() && !bytes[cursor].is_ascii_whitespace() && bytes[cursor] != b'='
        {
            cursor += 1;
        }
        let name = &input[name_start..cursor];
        while cursor < bytes.len() && bytes[cursor].is_ascii_whitespace() {
            cursor += 1;
        }
        if name.is_empty() || bytes.get(cursor) != Some(&b'=') {
            return Err(invalid_xml("malformed node attribute"));
        }
        cursor += 1;
        while cursor < bytes.len() && bytes[cursor].is_ascii_whitespace() {
            cursor += 1;
        }
        let quote = *bytes
            .get(cursor)
            .filter(|quote| matches!(quote, b'"' | b'\''))
            .ok_or_else(|| invalid_xml("unquoted node attribute"))?;
        cursor += 1;
        let value_start = cursor;
        while cursor < bytes.len() && bytes[cursor] != quote {
            cursor += 1;
        }
        if cursor >= bytes.len() {
            return Err(invalid_xml("unterminated node attribute"));
        }
        attributes.insert(
            name.to_string(),
            decode_entities(&input[value_start..cursor]),
        );
        cursor += 1;
    }
    Ok(attributes)
}

fn decode_entities(value: &str) -> String {
    value
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&amp;", "&")
}

fn invalid_xml(detail: &str) -> EmulatorFailure {
    EmulatorFailure::new(
        "provider_incompatible",
        format!("Android returned an invalid accessibility tree: {detail}."),
        ["Retry the snapshot after the visible screen settles."],
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::terminal_host::emulator::accessibility::MAX_AX_OUTPUT_BYTES;

    #[test]
    fn normalizes_nodes_and_redacts_password_text() {
        let xml = br#"<?xml version="1.0"?><hierarchy><node class="android.widget.FrameLayout" bounds="[0,0][100,200]"><node class="android.widget.EditText" text="hunter2" content-desc="Password" password="true" clickable="true" /></node></hierarchy>"#;
        let tree = normalize_uiautomator_tree(xml).unwrap();
        assert!(!tree.contains("hunter2"));
        let value: Value = serde_json::from_str(&tree).unwrap();
        let secure = &value[0]["children"][0];
        assert_eq!(secure["text"], REDACTED_VALUE);
        assert_eq!(secure["contentDescription"], REDACTED_VALUE);
        assert_eq!(secure["secure"], true);
        assert_eq!(value[0]["bounds"]["bottom"], 200);
    }

    #[test]
    fn password_label_redacts_editable_text_without_a_provider_flag() {
        let xml = br#"<hierarchy><node class="android.widget.EditText" text="hunter2" content-desc="Password" password="false" /></hierarchy>"#;
        let tree = normalize_uiautomator_tree(xml).unwrap();
        assert!(!tree.contains("hunter2"));
        let value: Value = serde_json::from_str(&tree).unwrap();
        assert_eq!(value[0]["text"], REDACTED_VALUE);
        assert_eq!(value[0]["secure"], true);
    }

    #[test]
    fn password_label_on_a_button_is_not_redacted() {
        let xml = br#"<hierarchy><node class="android.widget.Button" text="Show" content-desc="Password" /></hierarchy>"#;
        let tree = normalize_uiautomator_tree(xml).unwrap();
        let value: Value = serde_json::from_str(&tree).unwrap();
        assert_eq!(value[0]["text"], "Show");
        assert_eq!(value[0]["contentDescription"], "Password");
        assert!(value[0].get("secure").is_none());
    }

    #[test]
    fn redacts_an_unflagged_password_input_by_its_identifier() {
        let xml = br#"<hierarchy><node class="android.widget.EditText" resource-id="dev.app:id/password_input" text="hunter2" /></hierarchy>"#;
        let tree = normalize_uiautomator_tree(xml).unwrap();
        assert!(!tree.contains("hunter2"));
        let value: Value = serde_json::from_str(&tree).unwrap();
        assert_eq!(value[0]["secure"], true);
    }

    #[test]
    fn caps_depth_and_node_count() {
        let mut xml = String::from("<hierarchy>");
        for _ in 0..MAX_AX_DEPTH + 5 {
            xml.push_str(r#"<node class="nested">"#);
        }
        for _ in 0..MAX_AX_DEPTH + 5 {
            xml.push_str("</node>");
        }
        for index in 0..MAX_AX_NODES + 20 {
            xml.push_str(&format!(r#"<node text="{index}" />"#));
        }
        xml.push_str("</hierarchy>");
        let tree = normalize_uiautomator_tree(xml.as_bytes()).unwrap();
        let value: Value = serde_json::from_str(&tree).unwrap();
        assert!(count_nodes(&value) <= MAX_AX_NODES);
        assert!(maximum_depth(&value) <= MAX_AX_DEPTH);
        assert!(tree.len() <= MAX_AX_OUTPUT_BYTES);
        assert!(tree.contains("\"truncated\": true"));
    }

    #[test]
    fn rejects_oversized_source_xml() {
        let xml = vec![b'x'; MAX_AX_INPUT_BYTES + 1];
        let error = normalize_uiautomator_tree(&xml).unwrap_err();
        assert_eq!(error.code, "provider_incompatible");
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
