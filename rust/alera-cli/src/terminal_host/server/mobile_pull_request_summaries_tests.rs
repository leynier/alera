use super::*;

fn review_node(state: &str, is_draft: bool, contexts: Value) -> Value {
    json!({
        "number": 7,
        "title": "Add fork indicators",
        "state": state,
        "url": "https://github.com/leynier/alera/pull/7",
        "isDraft": is_draft,
        "mergeable": "MERGEABLE",
        "commits": {"nodes": [{"commit": {"statusCheckRollup": {"contexts": {"nodes": contexts}}}}]},
    })
}

fn check_run(name: &str, status: &str, conclusion: &str) -> Value {
    json!({"__typename": "CheckRun", "name": name, "status": status, "conclusion": conclusion})
}

#[test]
fn counts_check_runs_like_the_desktop_summary() {
    let contexts = vec![
        check_run("build", "COMPLETED", "SUCCESS"),
        check_run("test", "IN_PROGRESS", ""),
        check_run("lint", "COMPLETED", "FAILURE"),
        check_run("audit", "COMPLETED", "STARTUP_FAILURE"),
        check_run("deploy", "COMPLETED", "SKIPPED"),
    ];
    let counts = count_check_contexts(&contexts);
    assert_eq!(counts.rollup, "failure");
    assert_eq!(counts.failed, 2);
    assert_eq!(counts.pending, 1);
    assert_eq!(counts.failing_names, vec!["lint", "audit"]);
}

#[test]
fn caps_failing_check_names_at_three() {
    let contexts = vec![
        check_run("a", "COMPLETED", "FAILURE"),
        check_run("b", "COMPLETED", "TIMED_OUT"),
        check_run("c", "COMPLETED", "CANCELLED"),
        check_run("d", "COMPLETED", "STALE"),
        check_run("e", "COMPLETED", "ACTION_REQUIRED"),
    ];
    let counts = count_check_contexts(&contexts);
    assert_eq!(counts.failed, 5);
    assert_eq!(counts.failing_names, vec!["a", "b", "c"]);
}

#[test]
fn pending_rollup_when_nothing_failed_yet() {
    let contexts = vec![
        check_run("build", "COMPLETED", "SUCCESS"),
        check_run("test", "QUEUED", ""),
        json!({"__typename": "StatusContext", "context": "legacy", "state": "EXPECTED"}),
    ];
    let counts = count_check_contexts(&contexts);
    assert_eq!(counts.rollup, "pending");
    assert_eq!(counts.pending, 2);
    assert_eq!(counts.failed, 0);
}

#[test]
fn counts_legacy_commit_statuses() {
    let contexts = vec![
        json!({"__typename": "StatusContext", "context": "legacy-ok", "state": "SUCCESS"}),
        json!({"__typename": "StatusContext", "context": "legacy-broken", "state": "ERROR"}),
    ];
    let counts = count_check_contexts(&contexts);
    assert_eq!(counts.rollup, "failure");
    assert_eq!(counts.failed, 1);
    assert_eq!(counts.failing_names, vec!["legacy-broken"]);
}

#[test]
fn empty_contexts_roll_up_to_none() {
    let counts = count_check_contexts(&[]);
    assert_eq!(counts.rollup, "none");
    assert_eq!(counts.pending, 0);
    assert_eq!(counts.failed, 0);
}

#[test]
fn summary_json_maps_display_state_and_mergeable() {
    let open = summary_json("ws-1", &review_node("OPEN", false, json!([])));
    assert_eq!(open["state"], "open");
    assert_eq!(open["checksRollup"], "none");
    assert_eq!(open["mergeable"], "MERGEABLE");
    assert_eq!(open["workspaceId"], "ws-1");
    assert_eq!(open["number"], 7);

    let draft = summary_json("ws-2", &review_node("OPEN", true, json!([])));
    assert_eq!(draft["state"], "draft");

    let merged = summary_json("ws-3", &review_node("MERGED", false, json!([])));
    assert_eq!(merged["state"], "merged");

    let closed = summary_json("ws-4", &review_node("CLOSED", false, json!([])));
    assert_eq!(closed["state"], "closed");
}

#[test]
fn linked_number_wins_and_dismissed_branch_match_hides() {
    let mut batch = BTreeMap::new();
    batch.insert(
        "review:9".to_string(),
        review_node("MERGED", false, json!([])),
    );
    batch.insert(
        "branch:feature/login".to_string(),
        review_node("OPEN", false, json!([])),
    );

    let linked = summary_snapshot(Some(9), None, "feature/login", &batch);
    assert_eq!(linked.unwrap()["state"], "MERGED");

    let detected = summary_snapshot(None, None, "feature/login", &batch);
    assert_eq!(detected.unwrap()["state"], "OPEN");

    // An unlinked review stays hidden until the user links it again.
    let dismissed = summary_snapshot(None, Some(7), "feature/login", &batch);
    assert!(dismissed.is_none());

    let unknown_branch = summary_snapshot(None, None, "other/branch", &batch);
    assert!(unknown_branch.is_none());
}

#[test]
fn closed_branch_match_never_autodetects_but_linked_number_does() {
    let mut batch = BTreeMap::new();
    batch.insert(
        "branch:main".to_string(),
        review_node("CLOSED", false, json!([])),
    );
    batch.insert(
        "review:7".to_string(),
        review_node("CLOSED", false, json!([])),
    );
    assert!(summary_snapshot(None, None, "main", &batch).is_none());
    assert!(summary_snapshot(Some(7), None, "main", &batch).is_some());
}
