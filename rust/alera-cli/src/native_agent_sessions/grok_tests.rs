use super::super::test_support::{outcome_for, session, Fixture};
use super::super::NativeSessionCleanupScope::*;
use super::super::PATH_TARGET;
use super::percent_decode;

#[test]
fn directory_names_decode_like_grok_encodes_them() {
    assert_eq!(
        percent_decode("%2Fhome%2Fuser%2F.alera%2Fa-b_c").as_deref(),
        Some("/home/user/.alera/a-b_c")
    );
    assert_eq!(percent_decode("%2"), None);
    assert_eq!(percent_decode("%zz"), None);
}

#[tokio::test]
async fn registered_sessions_use_the_grok_delete_command() {
    let fixture = Fixture::new();
    let outcomes = fixture
        .run(
            RegisteredSessions,
            "/work/app",
            vec![session("grok", "019a-1")],
        )
        .await;
    assert_eq!(outcome_for(&outcomes, "grok", "019a-1").result, Ok(()));
    assert_eq!(fixture.argv(), vec!["grok sessions delete 019a-1"]);
}

#[tokio::test]
async fn path_scope_deletes_only_the_exact_workspace_directory_sessions() {
    let fixture = Fixture::new();
    let sessions = fixture.home().join(".grok/sessions");
    std::fs::create_dir_all(sessions.join("%2Fwork%2Fapp/019a-1")).unwrap();
    std::fs::create_dir_all(sessions.join("%2Fwork%2Fapp/019a-2")).unwrap();
    std::fs::create_dir_all(sessions.join("%2Fwork%2Fapp-sibling/019a-3")).unwrap();
    std::fs::create_dir_all(sessions.join("%2Fwork%2Fapp%2Fsub/019a-4")).unwrap();

    let outcomes = fixture.run(WorkspacePath, "/work/app", Vec::new()).await;

    assert_eq!(outcome_for(&outcomes, "grok", PATH_TARGET).result, Ok(()));
    let grok = fixture
        .argv()
        .into_iter()
        .filter(|argv| argv.starts_with("grok"))
        .collect::<Vec<_>>();
    assert_eq!(
        grok,
        vec!["grok sessions delete 019a-1", "grok sessions delete 019a-2"]
    );
    assert!(
        sessions.join("%2Fwork%2Fapp/019a-1").exists(),
        "grok deletes, not us"
    );
}
