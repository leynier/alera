use serde_json::json;

use super::{parse_workflow_yaml, WORKFLOW_DOCUMENT_MAX_BYTES};

#[test]
fn workflow_yaml_preserves_portable_scalars_and_multiline_instructions() {
    let value = parse_workflow_yaml(
        "version: 1\nname: Quick Fix\ninstructions: |\n  Inspect first.\n  Preserve work.\n\
         enabled: true\noptional: null\nvalues: [false, 2, 1.5, 'true', yes]\n",
    )
    .unwrap();
    assert_eq!(
        value,
        json!({
            "version": 1,
            "name": "Quick Fix",
            "instructions": "Inspect first.\nPreserve work.\n",
            "enabled": true,
            "optional": null,
            "values": [false, 2, 1.5, "true", "yes"]
        })
    );
    assert_eq!(
        parse_workflow_yaml(r#"{"version": 1, "roles": []}"#).unwrap(),
        json!({"version": 1, "roles": []})
    );
}

#[test]
fn workflow_yaml_rejects_aliases_tags_merges_and_multiple_documents() {
    for source in [
        "a: &a [1]\nb: *a",
        "a: *missing",
        "a: !!str 1",
        "a: !include https://example.test/remote",
        "a: !local [1]",
        "a: !local {b: 1}",
        "a: {<<: {value: 1}}",
        "a: 1\n---\nb: 2",
        "a: 1\na: 2",
        "a: {b: 1, b: 2}",
        "1: value",
        "? [a, b]\n: value",
    ] {
        assert!(parse_workflow_yaml(source).is_err(), "{source}");
    }
}

#[test]
fn workflow_yaml_rejects_invalid_empty_and_non_mapping_documents() {
    for source in ["", "  # empty", "[]", "null", "text", "a: [", "a: \0"] {
        assert!(parse_workflow_yaml(source).is_err(), "{source:?}");
    }
}

#[test]
fn workflow_yaml_limits_bytes_nodes_and_nesting_before_tree_expansion() {
    assert!(parse_workflow_yaml(&" ".repeat(WORKFLOW_DOCUMENT_MAX_BYTES + 1)).is_err());
    let deep = format!("a: {}0{}", "[".repeat(32), "]".repeat(32));
    assert!(parse_workflow_yaml(&deep)
        .unwrap_err()
        .to_string()
        .contains("nesting"));
    let extreme = format!("a: {}0{}", "[".repeat(1000), "]".repeat(1000));
    assert!(parse_workflow_yaml(&extreme).is_err());
    let many = format!("a: [{}]", vec!["0"; 8192].join(","));
    assert!(parse_workflow_yaml(&many)
        .unwrap_err()
        .to_string()
        .contains("node"));
    assert!(parse_workflow_yaml("a: [1, [2, {b: true}]]").is_ok());
}

#[test]
fn workflow_yaml_errors_do_not_echo_scalar_contents() {
    let error = parse_workflow_yaml("a: [private-secret-marker").unwrap_err();
    let message = error.to_string();
    assert!(!message.contains("private-secret-marker"));
    assert!(message.contains("line"));
}
