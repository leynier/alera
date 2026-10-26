use super::super::test_support::{outcome_for, sqlite_fixture, Fixture};
use super::super::NativeSessionCleanupScope::*;
use super::super::PATH_TARGET;

#[tokio::test]
async fn path_scope_deletes_top_level_v1_and_v2_sessions_for_the_exact_directory() {
    let mut fixture = Fixture::new();
    let data_home = fixture.temp.path().join("data");
    fixture
        .variables
        .insert("XDG_DATA_HOME".into(), data_home.to_string_lossy().into());
    sqlite_fixture(
        &data_home.join("opencode/opencode.db"),
        &[
            "CREATE TABLE session (id TEXT PRIMARY KEY, parent_id TEXT, directory TEXT NOT NULL)",
            "CREATE TABLE session_v2 (id TEXT PRIMARY KEY, parent_id TEXT, directory TEXT NOT NULL)",
            "INSERT INTO session VALUES ('ses_v1', NULL, '/work/app')",
            "INSERT INTO session VALUES ('ses_child', 'ses_v1', '/work/app')",
            "INSERT INTO session VALUES ('ses_sibling', NULL, '/work/app2')",
            "INSERT INTO session_v2 VALUES ('ses_v2', NULL, '/work/app')",
        ],
    )
    .await;

    let outcomes = fixture.run(WorkspacePath, "/work/app", Vec::new()).await;

    assert_eq!(
        outcome_for(&outcomes, "opencode", PATH_TARGET).result,
        Ok(())
    );
    let opencode = fixture
        .argv()
        .into_iter()
        .filter(|argv| argv.starts_with("opencode"))
        .collect::<Vec<_>>();
    assert_eq!(
        opencode,
        vec![
            "opencode session delete ses_v1",
            "opencode session delete ses_v2"
        ]
    );
}

#[tokio::test]
async fn a_missing_v2_table_does_not_hide_v1_sessions() {
    let fixture = Fixture::new();
    sqlite_fixture(
        &fixture.home().join(".local/share/opencode/opencode.db"),
        &[
            "CREATE TABLE session (id TEXT PRIMARY KEY, parent_id TEXT, directory TEXT NOT NULL)",
            "INSERT INTO session VALUES ('ses_v1', NULL, '/work/app')",
        ],
    )
    .await;

    let outcomes = fixture.run(WorkspacePath, "/work/app", Vec::new()).await;

    assert_eq!(outcome_for(&outcomes, "opencode", "ses_v1").result, Ok(()));
    assert_eq!(
        outcome_for(&outcomes, "opencode", PATH_TARGET).result,
        Ok(())
    );
}

#[tokio::test]
async fn a_changed_schema_is_reported_without_blocking_other_tables() {
    let fixture = Fixture::new();
    sqlite_fixture(
        &fixture.home().join(".local/share/opencode/opencode.db"),
        &[
            "CREATE TABLE session (id TEXT PRIMARY KEY, cwd TEXT)",
            "CREATE TABLE session_v2 (id TEXT PRIMARY KEY, parent_id TEXT, directory TEXT NOT NULL)",
            "INSERT INTO session_v2 VALUES ('ses_v2', NULL, '/work/app')",
        ],
    )
    .await;

    let outcomes = fixture.run(WorkspacePath, "/work/app", Vec::new()).await;

    assert!(outcome_for(&outcomes, "opencode", PATH_TARGET)
        .result
        .is_err());
    assert_eq!(outcome_for(&outcomes, "opencode", "ses_v2").result, Ok(()));
}
