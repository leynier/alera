use super::{branch_array, looks_like_collision};
use serde_json::json;

#[test]
fn detects_workspace_branch_collision_errors() {
    assert!(looks_like_collision("Branch already exists"));
    assert!(looks_like_collision("A workspace for branch foo exists"));
    assert!(!looks_like_collision("Permission denied"));
}

#[test]
fn branch_array_ignores_non_string_values() {
    assert_eq!(
        branch_array(&json!({"branches": ["main", 42, "dev"]}), "branches")
            .into_iter()
            .collect::<Vec<_>>(),
        vec!["dev", "main"]
    );
}
