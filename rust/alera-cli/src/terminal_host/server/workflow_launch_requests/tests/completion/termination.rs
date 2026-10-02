use super::*;

#[tokio::test]
async fn retained_workflow_terminal_notifies_clients_without_removing_the_tab() {
    let (fixture, launch, _token) = accepted_workflow().await;
    let workspace_id = launch.request.workspace_id.clone();
    let (mut actor, _commands, mut responses) = actor_for(&fixture).await;
    let mut session =
        crate::terminal_host::session::Session::driver_test_stub(&launch.terminal_handle, 80, 24);
    session.workspace_id = workspace_id;
    session.tab_id = launch.terminal_handle.clone();
    session.clients.insert(1);
    actor
        .sessions
        .insert(launch.terminal_handle.clone(), session);
    actor
        .terminate_sessions_for_tab(&launch.terminal_handle)
        .await;
    assert!(!actor.sessions.contains_key(&launch.terminal_handle));
    assert!(fixture
        .store
        .find_workspace_tab(&launch.terminal_handle)
        .await
        .unwrap()
        .is_some());
    let frames = std::iter::from_fn(|| responses.try_recv().ok())
        .filter_map(|frame| frame.as_json())
        .collect::<Vec<_>>();
    assert!(frames.iter().any(|frame| {
        frame["event"] == "terminalSessionRemoved"
            && frame["payload"]["sessionId"] == launch.terminal_handle
    }));
}

#[tokio::test]
async fn explicit_terminate_notifies_every_attached_workflow_client() {
    let (fixture, launch, _token) = accepted_workflow().await;
    let (mut actor, _commands, mut first_responses) = actor_for(&fixture).await;
    let (second_client, mut second_responses) = ClientHandle::test_channels();
    actor.clients.insert(2, local_client(second_client));
    let mut session =
        crate::terminal_host::session::Session::driver_test_stub(&launch.terminal_handle, 80, 24);
    session.workspace_id = launch.request.workspace_id.clone();
    session.tab_id = launch.terminal_handle.clone();
    session.clients.extend([1, 2]);
    actor
        .sessions
        .insert(launch.terminal_handle.clone(), session);

    assert_eq!(
        actor
            .handle_request(
                1,
                "terminate",
                &json!({"sessionId": launch.terminal_handle}),
            )
            .await
            .unwrap(),
        json!({})
    );
    assert!(!actor.sessions.contains_key(&launch.terminal_handle));
    assert!(fixture
        .store
        .find_workspace_tab(&launch.terminal_handle)
        .await
        .unwrap()
        .is_some());
    for responses in [&mut first_responses, &mut second_responses] {
        let frames = std::iter::from_fn(|| responses.try_recv().ok())
            .filter_map(|frame| frame.as_json())
            .collect::<Vec<_>>();
        assert!(frames.iter().any(|frame| {
            frame["event"] == "terminalSessionRemoved"
                && frame["payload"]["sessionId"] == launch.terminal_handle
        }));
    }
}
