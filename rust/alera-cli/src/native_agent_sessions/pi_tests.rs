use super::super::test_support::{outcome_for, session, write, Fixture};
use super::super::NativeSessionCleanupScope::*;
use super::super::PATH_TARGET;
use super::encoded_workspace_dir;

fn header(id: &str, cwd: &str) -> String {
    format!("{{\"type\":\"session\",\"version\":3,\"id\":\"{id}\",\"cwd\":\"{cwd}\"}}\n{{\"type\":\"message\"}}\n")
}

#[test]
fn workspace_directories_are_encoded_like_pi() {
    assert_eq!(
        encoded_workspace_dir("/home/u/.alera/workspaces/app"),
        "--home-u-.alera-workspaces-app--"
    );
    assert_eq!(encoded_workspace_dir("C:\\work\\app"), "--C--work-app--");
}

#[tokio::test]
async fn registered_sessions_are_removed_by_file_name_id() {
    let fixture = Fixture::new();
    let sessions = fixture.home().join(".pi/agent/sessions");
    let mine = sessions.join("--work-app--/2026-01-01T00-00-00-000Z_s1.jsonl");
    let other = sessions.join("--work-app--/2026-01-01T00-00-00-000Z_s2.jsonl");
    write(&mine, &header("s1", "/work/app"));
    write(&other, &header("s2", "/work/app"));

    let outcomes = fixture
        .run(RegisteredSessions, "/work/app", vec![session("pi", "s1")])
        .await;

    assert_eq!(outcome_for(&outcomes, "pi", "s1").result, Ok(()));
    assert!(!mine.exists());
    assert!(other.exists());
}

#[tokio::test]
async fn path_scope_removes_only_files_whose_header_names_the_exact_path() {
    let fixture = Fixture::new();
    let sessions = fixture.home().join(".pi/agent/sessions");
    // `/work/app-x` and `/work/app/x` share one encoded directory.
    let shared = sessions.join("--work-app-x--");
    let mine = shared.join("t_s1.jsonl");
    let collision = shared.join("t_s2.jsonl");
    write(&mine, &header("s1", "/work/app/x"));
    write(&collision, &header("s2", "/work/app-x"));
    let whole = sessions.join("--work-app--/t_s3.jsonl");
    write(&whole, &header("s3", "/work/app"));

    let mut nested = session("pi", "s1");
    nested.cwd = Some("/work/app/x".into());
    let outcomes = fixture.run(WorkspacePath, "/work/app", vec![nested]).await;

    assert_eq!(outcome_for(&outcomes, "pi", PATH_TARGET).result, Ok(()));
    assert!(!mine.exists());
    assert!(!whole.exists());
    assert!(!sessions.join("--work-app--").exists());
    assert!(collision.exists());
}

#[tokio::test]
async fn a_flat_session_dir_and_preserved_sessions_are_honored() {
    let mut fixture = Fixture::new();
    let flat = fixture.temp.path().join("pi-sessions");
    fixture.variables.insert(
        "PI_CODING_AGENT_SESSION_DIR".into(),
        flat.to_string_lossy().into(),
    );
    write(&flat.join("t_s1.jsonl"), &header("s1", "/work/app"));
    write(&flat.join("t_keep.jsonl"), &header("keep", "/work/app"));
    write(&flat.join("t_s2.jsonl"), &header("s2", "/work/app2"));

    let outcomes = fixture
        .run_preserving(
            WorkspacePath,
            "/work/app",
            Vec::new(),
            vec![session("pi", "keep")],
        )
        .await;

    assert_eq!(outcome_for(&outcomes, "pi", PATH_TARGET).result, Ok(()));
    assert!(!flat.join("t_s1.jsonl").exists());
    assert!(flat.join("t_keep.jsonl").exists());
    assert!(flat.join("t_s2.jsonl").exists());
}
