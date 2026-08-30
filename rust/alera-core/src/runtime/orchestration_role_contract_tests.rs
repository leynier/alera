use serde_json::{json, Value};

use super::{RoleContractSnapshot, RoleContractV1};

pub(super) fn contract() -> RoleContractV1 {
    serde_json::from_value(json!({
        "version": 1, "id": "implementer", "revision": 1, "name": "Implementer",
        "purpose": "Implement a scoped change.", "instructions": "Run the focused tests.",
        "inputSchema": {"type": "object", "properties": {"objective": {"type": "string", "minLength": 1}},
            "required": ["objective"], "additionalProperties": false},
        "resultSchema": {"type": "object", "properties": {"summary": {"type": "string", "minLength": 1}},
            "required": ["summary"]},
        "requiredArtifacts": ["docs/result.md"],
        "checklist": [{"id": "tests", "description": "Focused tests pass."}]
    })).unwrap()
}

pub(super) fn snapshot() -> RoleContractSnapshot {
    RoleContractSnapshot::freeze(contract(), json!({"objective": "Fix the bug"})).unwrap()
}

pub(super) fn result() -> Value {
    json!({"completionKind": "success", "summary": "Fixed the bug", "artifacts": ["docs/result.md"],
        "filesModified": ["src/feature.rs"],
        "validation": [{"id": "tests", "passed": true, "evidence": "cargo test: 3 passed"}]})
}

#[test]
fn role_contract_freezes_validated_inputs_and_has_stable_identity() {
    let original = snapshot();
    original.validate().unwrap();
    let restored: RoleContractSnapshot =
        serde_json::from_str(&serde_json::to_string(&original).unwrap()).unwrap();
    assert_eq!(original, restored);
    assert_eq!(original.digest.len(), 64);
    let mut mutated = restored;
    mutated.contract.instructions = "Changed".into();
    assert!(mutated.validate().is_err());
    assert_ne!(
        RoleContractSnapshot::freeze(mutated.contract, mutated.inputs)
            .unwrap()
            .digest,
        original.digest
    );
    let text = original.worker_instructions().unwrap();
    assert!(text.contains("Fix the bug"));
    assert!(text.contains("Focused tests pass."));
    assert!(text.contains(&original.digest));
}

#[test]
fn role_contract_rejects_invalid_inputs_versions_and_unknown_fields() {
    for inputs in [
        json!({}),
        json!({"objective": 42}),
        json!({"objective": ""}),
        json!({"objective": "ok", "other": true}),
    ] {
        assert!(RoleContractSnapshot::freeze(contract(), inputs).is_err());
    }
    for (key, value) in [
        ("version", json!(2)),
        ("revision", json!(0)),
        ("id", json!("../role")),
        ("name", json!(" ")),
        ("instructions", json!("")),
    ] {
        let mut definition = serde_json::to_value(contract()).unwrap();
        definition[key] = value;
        assert!(
            serde_json::from_value::<RoleContractV1>(definition)
                .unwrap()
                .validate()
                .is_err(),
            "{key}"
        );
    }
    for key in ["hooks", "provider", "command", "credentials", "include"] {
        let mut definition = serde_json::to_value(contract()).unwrap();
        definition[key] = json!("forbidden");
        assert!(
            serde_json::from_value::<RoleContractV1>(definition).is_err(),
            "{key}"
        );
    }
}

#[test]
fn role_contract_rejects_unsafe_schema_keywords_at_every_depth() {
    for keyword in [
        "$ref",
        "$dynamicRef",
        "$defs",
        "pattern",
        "patternProperties",
        "allOf",
        "anyOf",
        "oneOf",
        "not",
        "if",
        "format",
        "unknown",
    ] {
        let mut definition = contract();
        definition.input_schema["properties"]["objective"][keyword] =
            json!("https://example.invalid/schema");
        assert!(definition.validate().is_err(), "{keyword}");
    }
    for schema in [
        json!({"type": "array", "items": {"type": "string"}}),
        json!({"type": "object", "required": ["missing"]}),
        json!({"type": "object", "additionalProperties": {"type": "string"}}),
        json!({"type": "object", "properties": {"values": {"type": "array"}}}),
        json!({"type": "object", "properties": {"x": {"type": ["string", "null"]}}}),
        json!({"type": "object", "minProperties": -1}),
        json!({"type": "object", "properties": {"x": {"type": "string", "minimum": 3}}}),
    ] {
        let mut definition = contract();
        definition.input_schema = schema;
        assert!(definition.validate().is_err());
    }
}

#[test]
fn role_contract_supports_bounded_objects_arrays_scalars_and_enums() {
    let mut definition = contract();
    definition.input_schema = json!({
        "type": "object", "additionalProperties": false,
        "properties": {"values": {"type": "array", "minItems": 1, "maxItems": 2,
            "items": {"type": "integer", "minimum": 0, "maximum": 5}},
            "mode": {"type": "string", "enum": ["quick", "full"]},
            "flag": {"type": "boolean"}, "empty": {"type": "null"}},
        "required": ["values", "mode"]
    });
    for input in [
        json!({"values": [1, 5], "mode": "full"}),
        json!({"values": [0], "mode": "quick", "flag": true, "empty": null}),
    ] {
        RoleContractSnapshot::freeze(definition.clone(), input).unwrap();
    }
    for input in [
        json!({"values": [6], "mode": "full"}),
        json!({"values": [1], "mode": "unknown"}),
        json!({"values": [1, 2, 3], "mode": "quick"}),
    ] {
        assert!(RoleContractSnapshot::freeze(definition.clone(), input).is_err());
    }
}

#[test]
fn role_contract_limits_size_nodes_and_depth() {
    let mut definition = contract();
    definition.instructions = "x".repeat(16385);
    assert!(definition.validate().is_err());
    let mut nested = json!({"type": "string"});
    for _ in 0..14 {
        nested = json!({"type": "object", "properties": {"child": nested}});
    }
    definition = contract();
    definition.input_schema = nested;
    assert!(definition.validate().is_err());
    definition = contract();
    definition.input_schema = json!({"type": "object", "properties": (0..129).map(|n| (format!("k{n}"), json!({"type": "string"}))).collect::<serde_json::Map<_, _>>()});
    assert!(definition.validate().is_err());
    let mut input = json!({});
    for _ in 0..26 {
        input = json!({"nested": input});
    }
    assert!(RoleContractSnapshot::freeze(contract(), input).is_err());
    assert!(
        RoleContractSnapshot::freeze(contract(), json!({"objective": "x".repeat(256 * 1024)}))
            .is_err()
    );
    assert!(snapshot()
        .validate_success_result(&" ".repeat(256 * 1024 + 1))
        .is_err());
}

#[test]
fn role_contract_artifacts_are_portable_unique_workspace_paths() {
    for path in [
        "../out.md",
        "/tmp/out",
        "a/../b",
        "a//b",
        "a/./b",
        "C:/out",
        "a\\b",
        "out:",
        ".git/config",
        "a/NUL.txt",
        "a/COM1",
        "a/b.",
        "a/b ",
        "https://example.com/file",
        "a/*",
        "a/\0b",
    ] {
        let mut definition = contract();
        definition.required_artifacts = vec![path.into()];
        assert!(definition.validate().is_err(), "{path}");
    }
    let mut definition = contract();
    definition.required_artifacts = vec!["Docs/result.md".into(), "docs/result.md".into()];
    assert!(definition.validate().is_err());
    definition = contract();
    definition.checklist.push(definition.checklist[0].clone());
    assert!(definition.validate().is_err());
}

#[test]
fn role_contract_completion_requires_schema_artifacts_and_passing_evidence() {
    let contract = snapshot();
    contract
        .validate_success_result(&result().to_string())
        .unwrap();
    for (key, value) in [
        ("summary", json!("")),
        ("completionKind", json!("failure")),
        ("completionKind", json!(null)),
        ("artifacts", json!([])),
        ("artifacts", json!(["../docs/result.md"])),
        ("artifacts", json!(["docs/result.md", "docs/result.md"])),
        ("validation", json!([])),
        (
            "validation",
            json!([{"id": "tests", "passed": false, "evidence": "failed"}]),
        ),
        (
            "validation",
            json!([{"id": "tests", "passed": true, "evidence": " "}]),
        ),
        (
            "validation",
            json!([{"id": "tests", "passed": true, "evidence": "ok"}, {"id": "tests", "passed": true, "evidence": "ok"}]),
        ),
        ("filesModified", json!([42])),
    ] {
        let mut invalid = result();
        invalid[key] = value;
        assert!(
            contract
                .validate_success_result(&invalid.to_string())
                .is_err(),
            "{key}"
        );
    }
}

#[test]
fn role_contract_validation_does_not_echo_rejected_private_values() {
    let error = RoleContractSnapshot::freeze(
        contract(),
        json!({"objective": 42, "private": "not-for-logs"}),
    )
    .unwrap_err();
    assert!(!error.to_string().contains("not-for-logs"));
}
