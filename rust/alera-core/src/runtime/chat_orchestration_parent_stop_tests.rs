use super::super::agent_chat_test_support::store_with_workspace;
use super::super::*;

use ChatOrchestrationTaskStatus as Status;

fn task(
    task_id: &str,
    parent_chat_id: &str,
    parent_task_id: Option<&str>,
) -> NewChatOrchestrationTask {
    NewChatOrchestrationTask {
        task_id: task_id.into(),
        kind: ChatOrchestrationTaskKind::Delegate,
        caller_scope: "desktop".into(),
        parent_task_id: parent_task_id.map(str::to_owned),
        parent_chat_id: Some(parent_chat_id.into()),
        child_chat_id: None,
        project_id: None,
        workspace_id: None,
        host_id: None,
        target: ChatOrchestrationTarget::Chat {
            chat_id: format!("child-{task_id}"),
        },
        title: None,
        role: None,
        brief: format!("work {task_id}"),
        notify: ChatOrchestrationNotify::Always,
        launch_options: None,
    }
}

async fn create(store: &RuntimeStore, value: NewChatOrchestrationTask) {
    assert!(matches!(
        store
            .create_chat_orchestration_task(value, None)
            .await
            .unwrap(),
        ChatOrchestrationCreateOutcome::Created(_)
    ));
}

async fn settle(
    store: &RuntimeStore,
    task_id: &str,
    to: Status,
) -> ChatOrchestrationTransitionOutcome {
    store
        .transition_chat_orchestration_task(
            task_id,
            &ChatOrchestrationTaskTransition::new([Status::Preparing, Status::Running], to),
        )
        .await
        .unwrap()
}

#[tokio::test]
async fn a_parent_stop_drops_both_cohorts_and_silences_the_work_under_it() {
    let (_directory, store) = store_with_workspace("ws").await;
    create(&store, task("sealed", "parent", None)).await;
    create(&store, task("open", "parent", None)).await;
    create(&store, task("running", "parent", None)).await;
    create(&store, task("grandchild", "child-running", Some("running"))).await;
    let mut message = task("message", "parent", None);
    message.kind = ChatOrchestrationTaskKind::Message;
    create(&store, message).await;
    create(&store, task("other", "other-parent", None)).await;

    settle(&store, "sealed", Status::Completed).await;
    let sealed = store
        .seal_chat_orchestration_wake("parent")
        .await
        .unwrap()
        .unwrap();
    settle(&store, "open", Status::Completed).await;
    settle(&store, "other", Status::Completed).await;

    let stop = store
        .stop_chat_orchestration_parent("parent")
        .await
        .unwrap();
    // Only unsettled delegated work the chat owns directly; a message to
    // another chat stays with that chat.
    assert_eq!(stop.task_ids, ["running"]);
    assert_eq!(stop.sealed_wake_message_ids, [sealed.client_message_id]);
    assert!(store
        .list_chat_orchestration_wakes_awaiting_delivery(Some("parent"))
        .await
        .unwrap()
        .is_empty());
    // Another parent keeps its wake.
    assert_eq!(
        store
            .list_chat_orchestration_wakes_awaiting_delivery(Some("other-parent"))
            .await
            .unwrap()
            .len(),
        1
    );

    // The stopped children settle later without waking anyone.
    for task_id in ["running", "grandchild"] {
        assert!(matches!(
            settle(&store, task_id, Status::Failed).await,
            ChatOrchestrationTransitionOutcome::Applied { wake: None, .. }
        ));
    }
    assert!(store
        .list_chat_orchestration_wakes_awaiting_delivery(Some("parent"))
        .await
        .unwrap()
        .is_empty());
    // A task delegated after the stop wakes the chat again.
    create(&store, task("after", "parent", None)).await;
    assert!(matches!(
        settle(&store, "after", Status::Completed).await,
        ChatOrchestrationTransitionOutcome::Applied { wake: Some(_), .. }
    ));
}
