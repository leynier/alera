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
fn workflow_yaml_accepts_json_surrogate_pairs_without_changing_literal_escapes() {
    let source = r#"{"emoji":"\ud83d\ude80", "\uD801\uDC37":"\"\ud83d\ude80\"", "literal":"\\ud83d\\ude80"}"#;
    assert_eq!(
        parse_workflow_yaml(source).unwrap(),
        json!({
            "emoji":"🚀", "𐐷":"\"🚀\"", "literal":r"\ud83d\ude80"
        })
    );
    assert_eq!(
        parse_workflow_yaml("literal: '\\ud83d\\ude80'").unwrap(),
        json!({"literal":r"\ud83d\ude80"})
    );
    assert_eq!(
        parse_workflow_yaml("literal: |\n  \\ud83d\\ude80\n").unwrap(),
        json!({"literal":"\\ud83d\\ude80\n"})
    );
}

#[test]
fn workflow_yaml_json_normalization_preserves_duplicate_and_escape_rejection() {
    for source in [
        r#"{"a":"\ud83d"}"#,
        r#"{"a":"\ude80"}"#,
        r#"{"a":"\ude80\ud83d"}"#,
        r#"{"a":"\ud83d\u0041"}"#,
        r#"{"a":"\ud83d\ud83d"}"#,
        r#"{"a":"\ud83d\ude80", "a":2}"#,
        r#"{"🚀":1, "\ud83d\ude80":2}"#,
        r#"{"<<":"\ud83d\ude80"}"#,
        r#"{"a":"\ud83d\ude80"} {"b":2}"#,
    ] {
        assert!(parse_workflow_yaml(source).is_err(), "{source}");
    }
}

#[test]
fn workflow_yaml_json_normalization_preserves_original_resource_limits() {
    let many = format!(
        r#"{{"emoji":"\ud83d\ude80","a":[{}]}}"#,
        vec!["0"; 8192].join(",")
    );
    assert!(parse_workflow_yaml(&many)
        .unwrap_err()
        .to_string()
        .contains("node"));
    let deep = format!(
        r#"{{"emoji":"\ud83d\ude80","a":{}0{}}}"#,
        "[".repeat(32),
        "]".repeat(32)
    );
    assert!(parse_workflow_yaml(&deep)
        .unwrap_err()
        .to_string()
        .contains("nesting"));
    let large = format!(
        r#"{{"a":"{}"}}"#,
        r"\ud83d\ude80".repeat(WORKFLOW_DOCUMENT_MAX_BYTES / 12)
    );
    assert!(large.len() > WORKFLOW_DOCUMENT_MAX_BYTES);
    assert!(parse_workflow_yaml(&large)
        .unwrap_err()
        .to_string()
        .contains("too large"));
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
