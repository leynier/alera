use super::super::app_helpers::flutter_state_error;
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

#[test]
fn runtime_errors_match_flutter_state_error_copy() {
    assert_eq!(
        flutter_state_error("AI text generation was canceled.".to_owned()),
        "Bad state: AI text generation was canceled."
    );
    assert_eq!(
        flutter_state_error("Bad state: Agent profile not found: profile-1".to_owned()),
        "Bad state: Agent profile not found: profile-1"
    );
}
