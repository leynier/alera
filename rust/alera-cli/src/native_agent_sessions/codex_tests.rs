use super::super::test_support::{outcome_for, session, sqlite_fixture, Fixture};
use super::super::NativeSessionCleanupScope::*;
use super::super::PATH_TARGET;

const REGISTERED: &str = "019a0000-0000-7000-8000-000000000001";
const IN_WORKSPACE: &str = "019a0000-0000-7000-8000-000000000002";
const SIBLING: &str = "019a0000-0000-7000-8000-000000000003";
const OLD_DATABASE: &str = "019a0000-0000-7000-8000-000000000004";

async fn seed_state(path: &std::path::Path, rows: &[(&str, &str)]) {
    let mut statements = vec![
        "CREATE TABLE threads (id TEXT PRIMARY KEY, cwd TEXT NOT NULL, title TEXT NOT NULL DEFAULT '')"
            .to_string(),
    ];
    for (id, cwd) in rows {
        statements.push(format!(
            "INSERT INTO threads (id, cwd) VALUES ('{id}', '{cwd}')"
        ));
    }
    let statements = statements.iter().map(String::as_str).collect::<Vec<_>>();
    sqlite_fixture(path, &statements).await;
}

#[tokio::test]
async fn registered_sessions_are_force_deleted_by_uuid() {
    let fixture = Fixture::new();
    let outcomes = fixture
        .run(
            RegisteredSessions,
            "/work/app",
            vec![session("codex", REGISTERED)],
        )
        .await;
    assert_eq!(outcome_for(&outcomes, "codex", REGISTERED).result, Ok(()));
    assert_eq!(
        fixture.argv(),
        vec![format!("codex delete --force {REGISTERED}")]
    );
}

#[tokio::test]
async fn non_uuid_ids_are_not_deleted_by_name() {
    let fixture = Fixture::new();
    let outcomes = fixture
        .run(
            RegisteredSessions,
            "/work/app",
            vec![session("codex", "my-session")],
        )
        .await;
    assert!(outcome_for(&outcomes, "codex", "my-session")
        .result
        .is_err());
    assert!(fixture.commands().is_empty());
}

#[tokio::test]
async fn path_scope_deletes_threads_from_the_newest_state_database_by_exact_cwd() {
    let mut fixture = Fixture::new();
    let codex_home = fixture.temp.path().join("codex-home");
    fixture
        .variables
        .insert("CODEX_HOME".into(), codex_home.to_string_lossy().into());
    seed_state(
        &codex_home.join("state_5.sqlite"),
        &[
            (REGISTERED, "/work/app"),
            (IN_WORKSPACE, "/work/app"),
            (SIBLING, "/work/app-sibling"),
        ],
    )
    .await;
    seed_state(
        &codex_home.join("state_4.sqlite"),
        &[(OLD_DATABASE, "/work/app")],
    )
    .await;

    let outcomes = fixture
        .run(
            WorkspacePath,
            "/work/app",
            vec![session("codex", REGISTERED)],
        )
        .await;

    assert_eq!(outcome_for(&outcomes, "codex", PATH_TARGET).result, Ok(()));
    let codex = fixture
        .commands()
        .into_iter()
        .filter(|command| command.program == "codex")
        .collect::<Vec<_>>();
    let deleted = codex
        .iter()
        .map(|command| command.args[2].as_str())
        .collect::<Vec<_>>();
    assert_eq!(deleted, vec![REGISTERED, IN_WORKSPACE]);
    assert_eq!(
        codex[0].env["CODEX_HOME"],
        codex_home.to_string_lossy().as_ref()
    );
}

#[tokio::test]
async fn an_unreadable_state_database_still_deletes_registered_ids() {
    let fixture = Fixture::new();
    let codex_home = fixture.home().join(".codex");
    super::super::test_support::write(&codex_home.join("state_5.sqlite"), "not a database");

    let outcomes = fixture
        .run(
            WorkspacePath,
            "/work/app",
            vec![session("codex", REGISTERED)],
        )
        .await;

    assert!(outcome_for(&outcomes, "codex", PATH_TARGET).result.is_err());
    assert_eq!(outcome_for(&outcomes, "codex", REGISTERED).result, Ok(()));
}

#[tokio::test]
async fn preserved_threads_survive_path_discovery() {
    let fixture = Fixture::new();
    let codex_home = fixture.home().join(".codex");
    seed_state(
        &codex_home.join("state_5.sqlite"),
        &[(IN_WORKSPACE, "/work/app"), (SIBLING, "/work/app")],
    )
    .await;

    fixture
        .run_preserving(
            WorkspacePath,
            "/work/app",
            vec![session("codex", REGISTERED)],
            vec![session("codex", SIBLING), session("codex", REGISTERED)],
        )
        .await;

    let deleted = fixture
        .commands()
        .into_iter()
        .filter(|command| command.program == "codex")
        .map(|command| command.args[2].clone())
        .collect::<Vec<_>>();
    assert_eq!(deleted, vec![IN_WORKSPACE.to_string()]);
}
