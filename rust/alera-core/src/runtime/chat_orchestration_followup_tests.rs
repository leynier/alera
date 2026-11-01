use serde_json::json;

use super::super::agent_chat_test_support::store_with_workspace;
use super::super::*;

async fn settled_task(
    store: &RuntimeStore,
    task_id: &str,
    parent: Option<&str>,
) -> ChatOrchestrationTask {
    let input = NewChatOrchestrationTask {
        task_id: task_id.into(),
        kind: ChatOrchestrationTaskKind::Delegate,
        caller_scope: "chat:parent".into(),
        parent_task_id: None,
        parent_chat_id: parent.map(str::to_owned),
        child_chat_id: Some("child".into()),
        project_id: Some("project".into()),
        workspace_id: Some("ws".into()),
        host_id: Some("local".into()),
        target: ChatOrchestrationTarget::Chat {
            chat_id: "child".into(),
        },
        title: Some("Review".into()),
        role: None,
        brief: "Review the parser.".into(),
        notify: ChatOrchestrationNotify::Always,
        launch_options: Some(json!({"cancellationPolicy": "human", "waitNotify": "always"})),
    };
    let ChatOrchestrationCreateOutcome::Created(task) = store
        .create_chat_orchestration_task(input, None)
        .await
        .unwrap()
    else {
        panic!("task was not created");
    };
    let mut running = ChatOrchestrationTaskTransition::new(
        [ChatOrchestrationTaskStatus::Preparing],
        ChatOrchestrationTaskStatus::Running,
    );
    running.child_turn_id = Some(format!("turn-{task_id}"));
    store
        .transition_chat_orchestration_task(&task.task_id, &running)
        .await
        .unwrap();
    let mut done = ChatOrchestrationTaskTransition::new(
        [ChatOrchestrationTaskStatus::Running],
        ChatOrchestrationTaskStatus::Completed,
    );
    done.result_text = Some("Done.".into());
    match store
        .transition_chat_orchestration_task(&task.task_id, &done)
        .await
        .unwrap()
    {
        ChatOrchestrationTransitionOutcome::Applied { task, .. } => task,
        other => panic!("not settled: {other:?}"),
    }
}

fn followup(task_id: &str, of: &str, turn: &str) -> ChatOrchestrationFollowup {
    ChatOrchestrationFollowup {
        task_id: task_id.into(),
        followup_of: of.into(),
        child_chat_id: "child".into(),
        child_turn_id: turn.into(),
        origin: "a background continuation".into(),
    }
}

#[tokio::test]
async fn a_followup_hangs_under_the_original_and_runs_on_its_turn() {
    let (_dir, store) = store_with_workspace("ws").await;
    let original = settled_task(&store, "original", Some("parent")).await;
    let ChatOrchestrationFollowupOutcome::Created(first) = store
        .create_chat_orchestration_followup(&followup("f1", "original", "turn-2"))
        .await
        .unwrap()
    else {
        panic!("follow-up was not created");
    };
    assert_eq!(first.kind, ChatOrchestrationTaskKind::Followup);
    assert_eq!(first.status, ChatOrchestrationTaskStatus::Running);
    assert_eq!(first.parent_task_id.as_deref(), Some("original"));
    assert_eq!(first.root_task_id, original.root_task_id);
    assert_eq!(first.child_turn_id.as_deref(), Some("turn-2"));
    assert_eq!(first.notify, ChatOrchestrationNotify::Always);
    assert_eq!(first.title.as_deref(), Some("Review"));
    let options = first.launch_options.clone().unwrap();
    assert_eq!(options["followupOfTaskId"], "original");
    assert!(options.get("waitNotify").is_none());
    assert_eq!(options["cancellationPolicy"], "human");

    // The same turn never opens a second follow-up, and an unsettled
    // follow-up keeps the next turn from opening one.
    assert!(matches!(
        store
            .create_chat_orchestration_followup(&followup("dup", "original", "turn-2"))
            .await
            .unwrap(),
        ChatOrchestrationFollowupOutcome::Exists
    ));
    assert!(matches!(
        store
            .create_chat_orchestration_followup(&followup("f2", "f1", "turn-3"))
            .await
            .unwrap(),
        ChatOrchestrationFollowupOutcome::Refused
    ));
    let mut done = ChatOrchestrationTaskTransition::new(
        [ChatOrchestrationTaskStatus::Running],
        ChatOrchestrationTaskStatus::Completed,
    );
    done.result_text = Some("Later.".into());
    store
        .transition_chat_orchestration_task("f1", &done)
        .await
        .unwrap();
    let ChatOrchestrationFollowupOutcome::Created(second) = store
        .create_chat_orchestration_followup(&followup("f2", "f1", "turn-3"))
        .await
        .unwrap()
    else {
        panic!("second follow-up was not created");
    };
    assert_eq!(second.parent_task_id.as_deref(), Some("original"));
    assert_eq!(second.launch_options.unwrap()["followupOfTaskId"], "f1");
    assert_eq!(
        store
            .latest_chat_orchestration_task_for_child("child")
            .await
            .unwrap()
            .unwrap()
            .task_id,
        "f2"
    );
}

#[tokio::test]
async fn a_followup_needs_a_settled_parented_task_its_person_did_not_stop() {
    let (_dir, store) = store_with_workspace("ws").await;
    settled_task(&store, "orphan", None).await;
    assert!(matches!(
        store
            .create_chat_orchestration_followup(&followup("f", "orphan", "turn-x"))
            .await
            .unwrap(),
        ChatOrchestrationFollowupOutcome::Refused
    ));
    settled_task(&store, "stopped", Some("parent")).await;
    sqlx::query(
        "UPDATE chatOrchestrationTasks SET launchOptionsJson = json_set(launchOptionsJson, \
         '$.parentStopped', json('true')) WHERE taskId = 'stopped'",
    )
    .execute(store.pool())
    .await
    .unwrap();
    assert!(matches!(
        store
            .create_chat_orchestration_followup(&followup("g", "stopped", "turn-y"))
            .await
            .unwrap(),
        ChatOrchestrationFollowupOutcome::Refused
    ));
}

#[tokio::test]
async fn advancing_a_task_turn_is_a_compare_and_set_that_keeps_the_chain_start() {
    let (_dir, store) = store_with_workspace("ws").await;
    let input = NewChatOrchestrationTask {
        task_id: "held".into(),
        kind: ChatOrchestrationTaskKind::Delegate,
        caller_scope: "desktop".into(),
        parent_task_id: None,
        parent_chat_id: Some("parent".into()),
        child_chat_id: Some("child".into()),
        project_id: None,
        workspace_id: Some("ws".into()),
        host_id: None,
        target: ChatOrchestrationTarget::Chat {
            chat_id: "child".into(),
        },
        title: None,
        role: None,
        brief: "Hold.".into(),
        notify: ChatOrchestrationNotify::Always,
        launch_options: None,
    };
    store
        .create_chat_orchestration_task(input, None)
        .await
        .unwrap();
    let mut running = ChatOrchestrationTaskTransition::new(
        [ChatOrchestrationTaskStatus::Preparing],
        ChatOrchestrationTaskStatus::Running,
    );
    running.child_turn_id = Some("t1".into());
    store
        .transition_chat_orchestration_task("held", &running)
        .await
        .unwrap();
    let before = store
        .chat_orchestration_task("held")
        .await
        .unwrap()
        .unwrap();
    let advanced = store
        .advance_chat_orchestration_task_turn("held", "t1", "t2")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(advanced.child_turn_id.as_deref(), Some("t2"));
    assert_eq!(advanced.revision, before.revision);
    assert_eq!(
        advanced.launch_options.as_ref().unwrap()["chainStartTurnId"],
        "t1"
    );
    assert!(store
        .advance_chat_orchestration_task_turn("held", "t1", "t3")
        .await
        .unwrap()
        .is_none());
    let again = store
        .advance_chat_orchestration_task_turn("held", "t2", "t3")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(again.launch_options.unwrap()["chainStartTurnId"], "t1");
}
