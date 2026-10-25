use super::test_support::{outcome_for, session, Fixture};
use super::{normalize_workspace_path, NativeSessionCleanupScope::*};

const UUID: &str = "019a0000-0000-7000-8000-000000000001";

#[tokio::test]
async fn unknown_agents_are_skipped_without_an_outcome() {
    let fixture = Fixture::new();
    let outcomes = fixture
        .run(
            RegisteredSessions,
            "/work/app",
            vec![session("gemini", "abc")],
        )
        .await;
    assert!(outcomes.is_empty(), "{outcomes:?}");
    assert!(fixture.commands().is_empty());
}

#[tokio::test]
async fn unusable_ids_are_rejected_before_any_command() {
    let fixture = Fixture::new();
    let outcomes = fixture
        .run(
            RegisteredSessions,
            "/work/app",
            vec![
                session("opencode", "--all"),
                session("opencode", "a;rm -rf"),
                session("grok", "../escape"),
                session("cursor", "a/b"),
            ],
        )
        .await;
    assert_eq!(outcomes.len(), 4);
    assert!(outcomes.iter().all(|outcome| outcome.result.is_err()));
    assert!(fixture.commands().is_empty());
}

#[tokio::test]
async fn legacy_opencode2_sessions_are_deleted_as_opencode() {
    let fixture = Fixture::new();
    let outcomes = fixture
        .run(
            RegisteredSessions,
            "/work/app",
            vec![session("opencode2", "ses_1")],
        )
        .await;
    assert_eq!(outcome_for(&outcomes, "opencode", "ses_1").result, Ok(()));
    assert_eq!(fixture.argv(), vec!["opencode session delete ses_1"]);
}

#[tokio::test]
async fn one_failing_agent_does_not_stop_the_others() {
    let fixture = Fixture::new();
    fixture.fail_on("ses_bad");
    let outcomes = fixture
        .run(
            RegisteredSessions,
            "/work/app",
            vec![
                session("opencode", "ses_bad"),
                session("opencode", "ses_good"),
                session("codex", UUID),
            ],
        )
        .await;
    assert!(outcome_for(&outcomes, "opencode", "ses_bad")
        .result
        .is_err());
    assert_eq!(
        outcome_for(&outcomes, "opencode", "ses_good").result,
        Ok(())
    );
    assert_eq!(outcome_for(&outcomes, "codex", UUID).result, Ok(()));
}

#[tokio::test]
async fn registered_scope_never_runs_path_discovery() {
    let fixture = Fixture::new();
    std::fs::create_dir_all(fixture.home().join(".claude/projects")).unwrap();
    let outcomes = fixture
        .run(RegisteredSessions, "/work/app", vec![session("amp", "T-1")])
        .await;
    assert_eq!(outcomes.len(), 1);
    assert_eq!(fixture.argv(), vec!["amp threads archive T-1"]);
}

#[tokio::test]
async fn path_scope_refuses_relative_and_root_paths() {
    for path in ["relative/app", "/", ""] {
        let fixture = Fixture::new();
        std::fs::create_dir_all(fixture.home().join(".claude/projects")).unwrap();
        let outcomes = fixture.run(WorkspacePath, path, Vec::new()).await;
        assert!(outcomes.is_empty(), "{path}: {outcomes:?}");
        assert!(fixture.commands().is_empty(), "{path}");
    }
}

#[tokio::test]
async fn path_scope_also_covers_registered_cwds_inside_the_workspace() {
    let fixture = Fixture::new();
    std::fs::create_dir_all(fixture.home().join(".claude")).unwrap();
    let mut inside = session("claude", "s1");
    inside.cwd = Some("/work/app/packages/api/".into());
    let mut sibling = session("claude", "s2");
    sibling.cwd = Some("/work/app-other".into());
    fixture
        .run(WorkspacePath, "/work/app/", vec![inside, sibling])
        .await;
    assert_eq!(
        fixture.argv(),
        vec![
            "claude purge /work/app --yes",
            "claude purge /work/app/packages/api --yes",
        ]
    );
}

#[test]
fn workspace_paths_lose_trailing_separators_but_keep_roots() {
    assert_eq!(normalize_workspace_path(" /work/app/ "), "/work/app");
    assert_eq!(normalize_workspace_path("C:\\work\\app\\"), "C:\\work\\app");
    assert_eq!(normalize_workspace_path("/"), "/");
    assert_eq!(normalize_workspace_path("C:\\"), "C:\\");
}

#[test]
fn first_failure_still_runs_every_later_target() {
    let mut ran = 0;
    let result = super::first_failure((0..3).map(|index| {
        ran += 1;
        if index == 0 {
            Err(super::CleanupFailure::new("filesystem", "first"))
        } else {
            Ok(())
        }
    }));
    assert_eq!(result.unwrap_err().detail, "first");
    assert_eq!(ran, 3);
}
