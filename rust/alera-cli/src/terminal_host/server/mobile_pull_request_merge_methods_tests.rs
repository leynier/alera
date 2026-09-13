use serde_json::json;

use super::*;

#[test]
fn maps_repository_merge_settings_in_desktop_order() {
    let value = json!({"mergeCommitAllowed": false, "squashMergeAllowed": true, "rebaseMergeAllowed": true});
    assert_eq!(map_repo_allowed(&value), Some(vec!["squash", "rebase"]));
    assert_eq!(
        map_repo_allowed(
            &json!({"mergeCommitAllowed": false, "squashMergeAllowed": false, "rebaseMergeAllowed": false})
        ),
        Some(Vec::new())
    );
    assert_eq!(map_repo_allowed(&json!({"squashMergeAllowed": true})), None);
}

#[test]
fn unconstrained_rules_defer_to_repository_settings() {
    assert_eq!(map_ruleset_allowed(&json!([[]])), Ok(None));
    assert_eq!(
        map_ruleset_allowed(
            &json!([[{"type": "pull_request", "parameters": {"required_approving_review_count": 1}}]])
        ),
        Ok(None)
    );
}

#[test]
fn rules_intersect_and_linear_history_forbids_merge_commits() {
    let rules = json!([[
        {"type": "pull_request", "parameters": {"allowed_merge_methods": ["merge", "squash"]}},
        {"type": "required_linear_history"}
    ]]);
    assert_eq!(
        map_ruleset_allowed(&rules),
        Ok(Some(BTreeSet::from(["squash"])))
    );
}

#[test]
fn malformed_rules_fail_closed() {
    assert!(map_ruleset_allowed(&json!("nope")).is_err());
    assert!(map_ruleset_allowed(&json!([{"type": "merge_method"}])).is_err());
    assert!(map_ruleset_allowed(
        &json!([{"type": "pull_request", "parameters": {"allowed_merge_methods": [1]}}])
    )
    .is_err());
    assert!(map_ruleset_allowed(&json!([{"type": "pull_request", "parameters": "x"}])).is_err());
}

#[test]
fn encodes_branch_names_like_uri_encode_component() {
    assert_eq!(encode_path_segment("feat/mobile pr"), "feat%2Fmobile%20pr");
    assert_eq!(encode_path_segment("release-1.0_x"), "release-1.0_x");
}
