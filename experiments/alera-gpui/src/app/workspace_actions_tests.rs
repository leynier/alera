use super::*;

#[test]
fn preferred_workspace_branch_uses_main_before_other_refs() {
    let branches = vec![
        "dev".to_owned(),
        "origin/main".to_owned(),
        "main".to_owned(),
    ];
    assert_eq!(
        preferred_workspace_branch(&branches).as_deref(),
        Some("main")
    );
}

#[test]
fn preferred_workspace_branch_falls_back_to_origin_main() {
    let branches = vec!["dev".to_owned(), "origin/main".to_owned()];
    assert_eq!(
        preferred_workspace_branch(&branches).as_deref(),
        Some("origin/main")
    );
}

#[test]
fn string_array_ignores_non_string_entries() {
    let value = json!({"branches": ["main", 42, "dev"]});
    assert_eq!(string_array(&value, "branches"), vec!["main", "dev"]);
}
