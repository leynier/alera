use super::super::test_support::{outcome_for, session, write, Fixture};
use super::super::NativeSessionCleanupScope::*;
use super::super::PATH_TARGET;
use super::unquote_yaml_scalar;

fn seed(state: &std::path::Path, id: &str, cwd: &str) {
    write(
        &state.join(id).join("workspace.yaml"),
        &format!("id: {id}\ncwd: {cwd}\ngit_root: {cwd}\n"),
    );
    write(&state.join(id).join("events.jsonl"), "{}");
}

#[test]
fn quoted_yaml_values_are_unquoted() {
    assert_eq!(unquote_yaml_scalar("/a b").as_deref(), Some("/a b"));
    assert_eq!(unquote_yaml_scalar("'/it''s'").as_deref(), Some("/it's"));
    assert_eq!(
        unquote_yaml_scalar("\"C:\\\\work\\\\app\"").as_deref(),
        Some("C:\\work\\app")
    );
}

#[tokio::test]
async fn a_session_held_by_a_live_process_is_skipped() {
    let mut fixture = Fixture::new();
    fixture.process_alive = |pid| pid == 4242;
    let state = fixture.home().join(".copilot/session-state");
    seed(&state, "running", "/work/app");
    write(&state.join("running/inuse.4242.lock"), "4242");
    seed(&state, "stale", "/work/app");
    write(&state.join("stale/inuse.1111.lock"), "1111");

    let outcomes = fixture
        .run(
            RegisteredSessions,
            "/work/app",
            vec![session("copilot", "running"), session("copilot", "stale")],
        )
        .await;

    assert!(outcome_for(&outcomes, "copilot", "running").result.is_err());
    assert_eq!(outcome_for(&outcomes, "copilot", "stale").result, Ok(()));
    assert!(state.join("running").exists());
    assert!(!state.join("stale").exists());
}

#[tokio::test]
async fn path_scope_matches_the_workspace_cwd_exactly_and_keeps_preserved_ones() {
    let mut fixture = Fixture::new();
    let home = fixture.temp.path().join("copilot-home");
    fixture
        .variables
        .insert("COPILOT_HOME".into(), home.to_string_lossy().into());
    let state = home.join("session-state");
    seed(&state, "mine", "/work/app");
    seed(&state, "quoted", "'/work/app'");
    seed(&state, "kept", "/work/app");
    seed(&state, "sibling", "/work/app-sibling");
    seed(&state, "nested", "/work/app/sub");
    write(&home.join("session-store.db"), "index");

    let outcomes = fixture
        .run_preserving(
            WorkspacePath,
            "/work/app",
            Vec::new(),
            vec![session("copilot", "kept")],
        )
        .await;

    assert_eq!(
        outcome_for(&outcomes, "copilot", PATH_TARGET).result,
        Ok(())
    );
    assert!(!state.join("mine").exists());
    assert!(!state.join("quoted").exists());
    assert!(state.join("kept").exists());
    assert!(state.join("sibling").exists());
    assert!(state.join("nested").exists());
    assert!(home.join("session-store.db").exists());
}
