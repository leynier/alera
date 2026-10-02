use super::WorkspaceShutdown;
use crate::managed_workspace::ManagedWorkspaceRemoveRequest;
use crate::terminal_host::host_error::HostError;
use crate::terminal_host::server::checkout_buffer_guards_tests::fixture;
use crate::terminal_host::session::Session;

#[tokio::test]
async fn captured_shutdown_survives_history_retry_without_recapture() {
    let (_root, mut actor) = fixture().await;
    let (release, wait) = tokio::sync::oneshot::channel();
    let mut session = Session::driver_test_stub("pointer", 80, 24);
    session.workspace_id = "task".into();
    session.tab_id = "pointer-tab".into();
    assert!(session.begin_checkpoint_job(tokio::spawn(async move {
        wait.await.map_err(|error| error.to_string())
    })));
    actor.sessions.insert("pointer".into(), session);
    let request = ManagedWorkspaceRemoveRequest {
        id: "task".into(),
        close_sessions: true,
        delete_branch: None,
        active_workspace_id: None,
    };
    let mut captured = WorkspaceShutdown::default();
    captured.fail_next_waits(1);
    let error = actor
        .prepare_workspace_session_shutdown_with_capture(&request, false, Some(captured))
        .await
        .err()
        .expect("history must finish before the pointer is removed");
    assert!(matches!(error, HostError::Conflict { code, .. } if code == "terminalHistoryPending"));
    assert!(actor.sessions.contains_key("pointer"));
    release.send(()).unwrap();
    let mut shutdown = tokio::time::timeout(std::time::Duration::from_secs(2), async {
        loop {
            match actor
                .prepare_workspace_session_shutdown(&request, false)
                .await
            {
                Ok(shutdown) => break shutdown,
                Err(HostError::Conflict { code, .. }) if code == "terminalHistoryPending" => {
                    tokio::task::yield_now().await;
                }
                Err(error) => panic!("unexpected cleanup error: {error}"),
            }
        }
    })
    .await
    .expect("cleanup must resume after the checkpoint finishes");
    assert!(!actor.sessions.contains_key("pointer"));
    assert_eq!(shutdown.closed_tab_ids, vec!["pointer-tab".to_string()]);
    let error = shutdown.wait().await.unwrap_err();
    assert!(
        error
            .wire_message()
            .contains("injected process inspection failure"),
        "the original shutdown ownership must survive the history retry"
    );
}
