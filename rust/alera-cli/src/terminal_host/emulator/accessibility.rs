use serde_json::Value;

use super::contract::{EmulatorFailure, EmulatorResult};

pub const MAX_AX_INPUT_BYTES: usize = 1024 * 1024;
pub const MAX_AX_OUTPUT_BYTES: usize = 128 * 1024;
pub const MAX_AX_NODES: usize = 500;
pub const MAX_AX_DEPTH: usize = 32;
pub const MAX_AX_STRING_BYTES: usize = 512;
pub const REDACTED_VALUE: &str = "[REDACTED]";

pub fn bounded_string(value: &str) -> String {
    if value.len() <= MAX_AX_STRING_BYTES {
        return value.to_string();
    }
    let mut end = MAX_AX_STRING_BYTES;
    while !value.is_char_boundary(end) {
        end -= 1;
    }
    value[..end].to_string()
}

pub fn bounded_tree_value(mut roots: Vec<Value>) -> EmulatorResult<Value> {
    if roots.is_empty() {
        return Ok(Value::Array(roots));
    }
    loop {
        let value = Value::Array(roots);
        let encoded = serde_json::to_vec_pretty(&value).map_err(tree_encoding_failure)?;
        if encoded.len() <= MAX_AX_OUTPUT_BYTES {
            return Ok(value);
        }
        roots = match value {
            Value::Array(roots) => roots,
            _ => unreachable!(),
        };
        if !drop_last_descendant(&mut roots) {
            return Err(EmulatorFailure::new(
                "provider_incompatible",
                "The emulator accessibility tree could not be reduced to a safe response size.",
                ["Simplify the visible screen and retry the snapshot."],
            ));
        }
    }
}

pub fn bounded_tree_text(roots: Vec<Value>) -> EmulatorResult<String> {
    serde_json::to_string_pretty(&bounded_tree_value(roots)?).map_err(tree_encoding_failure)
}

fn drop_last_descendant(roots: &mut Vec<Value>) -> bool {
    let Some(last) = roots.last_mut() else {
        return false;
    };
    if drop_from_node(last) {
        return true;
    }
    if roots.len() > 1 {
        roots.pop();
        if let Some(last) = roots.last_mut() {
            mark_truncated(last);
        }
        return true;
    }
    false
}

fn drop_from_node(node: &mut Value) -> bool {
    let Some(object) = node.as_object_mut() else {
        return false;
    };
    let Some(children) = object.get_mut("children").and_then(Value::as_array_mut) else {
        return false;
    };
    let Some(last) = children.last_mut() else {
        return false;
    };
    if drop_from_node(last) {
        return true;
    }
    children.pop();
    object.insert("truncated".to_string(), Value::Bool(true));
    true
}

pub fn mark_truncated(node: &mut Value) {
    if let Some(object) = node.as_object_mut() {
        object.insert("truncated".to_string(), Value::Bool(true));
    }
}

fn tree_encoding_failure(error: serde_json::Error) -> EmulatorFailure {
    EmulatorFailure::new(
        "provider_incompatible",
        format!("Could not encode the emulator accessibility tree: {error}"),
        ["Retry the snapshot."],
    )
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn bounded_strings_preserve_utf8_boundaries() {
        let value = "é".repeat(MAX_AX_STRING_BYTES);
        let bounded = bounded_string(&value);
        assert!(bounded.len() <= MAX_AX_STRING_BYTES);
        assert!(bounded.is_char_boundary(bounded.len()));
    }

    #[test]
    fn oversized_trees_drop_tail_nodes_and_mark_the_parent() {
        let large = "x".repeat(MAX_AX_STRING_BYTES);
        let children: Vec<Value> = (0..MAX_AX_NODES)
            .map(|index| json!({"label": format!("{index}-{large}"), "children": []}))
            .collect();
        let value = bounded_tree_value(vec![json!({"children": children})]).unwrap();
        let encoded = serde_json::to_vec_pretty(&value).unwrap();
        assert!(encoded.len() <= MAX_AX_OUTPUT_BYTES);
        assert_eq!(value[0]["truncated"], true);
        assert!(value[0]["children"].as_array().unwrap().len() < MAX_AX_NODES);
    }
}
