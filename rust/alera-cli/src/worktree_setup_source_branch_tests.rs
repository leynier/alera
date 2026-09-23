use super::{preferred_source_branch_candidates, resolve_configured_source_branch};

#[test]
fn preferred_source_branch_candidates_pair_local_and_origin() {
    assert!(preferred_source_branch_candidates("  ").is_empty());
    assert_eq!(
        preferred_source_branch_candidates("develop"),
        vec!["develop".to_string(), "origin/develop".to_string()]
    );
    assert_eq!(
        preferred_source_branch_candidates("origin/develop"),
        vec!["origin/develop".to_string(), "develop".to_string()]
    );
    assert_eq!(
        preferred_source_branch_candidates("origin/"),
        vec!["origin/".to_string()]
    );
}

#[test]
fn resolve_configured_source_branch_uses_origin_twin_without_main_fallback() {
    let branches = vec!["main".to_string(), "origin/develop".to_string()];
    assert_eq!(
        resolve_configured_source_branch(&branches, "develop").as_deref(),
        Some("origin/develop")
    );
    assert_eq!(
        resolve_configured_source_branch(&branches, "missing").as_deref(),
        None
    );
    assert_eq!(
        resolve_configured_source_branch(&["develop".into()], "origin/develop").as_deref(),
        Some("develop")
    );
}
