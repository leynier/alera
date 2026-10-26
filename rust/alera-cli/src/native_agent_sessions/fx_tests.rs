use std::fs::File;
use std::path::Path;

use sha2::{Digest, Sha256};

use super::super::test_support::{outcome_for, session, write, Fixture};
use super::super::NativeSessionCleanupScope::*;
use super::super::PATH_TARGET;

fn seed(sessions: &Path, id: &str, workspace_root: &str) {
    write(
        &sessions.join(id).join("session.json"),
        &format!("{{\"id\":\"{id}\",\"workspace_root\":\"{workspace_root}\"}}"),
    );
    write(&sessions.join(id).join("session.lock"), "");
}

fn continue_pointer(fx_home: &Path, workspace: &str) -> std::path::PathBuf {
    fx_home
        .join("continue")
        .join(hex::encode(Sha256::digest(workspace.as_bytes())))
}

#[tokio::test]
async fn a_session_locked_by_a_running_fx_is_skipped() {
    let fixture = Fixture::new();
    let sessions = fixture.home().join(".fx/sessions");
    seed(&sessions, "running", "/work/app");
    seed(&sessions, "idle", "/work/app");
    let held = File::open(sessions.join("running/session.lock")).unwrap();
    held.lock().unwrap();

    let outcomes = fixture
        .run(
            RegisteredSessions,
            "/work/app",
            vec![session("fx", "running"), session("fx", "idle")],
        )
        .await;

    assert!(outcome_for(&outcomes, "fx", "running").result.is_err());
    assert_eq!(outcome_for(&outcomes, "fx", "idle").result, Ok(()));
    assert!(sessions.join("running").exists());
    assert!(!sessions.join("idle").exists());
    drop(held);
}

#[tokio::test]
async fn path_scope_removes_exact_workspace_sessions_and_their_continue_pointer() {
    let fixture = Fixture::new();
    let fx_home = fixture.home().join(".fx");
    let sessions = fx_home.join("sessions");
    seed(&sessions, "-dashed", "/work/app");
    seed(&sessions, "kept", "/work/app");
    seed(&sessions, "sibling", "/work/app-sibling");
    write(&continue_pointer(&fx_home, "/work/app"), "-dashed");
    write(&continue_pointer(&fx_home, "/work/app-sibling"), "sibling");

    let outcomes = fixture
        .run_preserving(
            WorkspacePath,
            "/work/app",
            Vec::new(),
            vec![session("fx", "kept")],
        )
        .await;

    assert_eq!(outcome_for(&outcomes, "fx", PATH_TARGET).result, Ok(()));
    assert_eq!(outcome_for(&outcomes, "fx", "-dashed").result, Ok(()));
    assert!(!sessions.join("-dashed").exists());
    assert!(sessions.join("kept").exists());
    assert!(sessions.join("sibling").exists());
    assert!(!continue_pointer(&fx_home, "/work/app").exists());
    assert!(continue_pointer(&fx_home, "/work/app-sibling").exists());
}

#[tokio::test]
async fn a_continue_pointer_naming_another_session_is_kept() {
    let fixture = Fixture::new();
    let fx_home = fixture.home().join(".fx");
    seed(&fx_home.join("sessions"), "old", "/work/app");
    write(&continue_pointer(&fx_home, "/work/app"), "newer");

    fixture
        .run(RegisteredSessions, "/work/app", vec![session("fx", "old")])
        .await;

    assert!(continue_pointer(&fx_home, "/work/app").exists());
}
