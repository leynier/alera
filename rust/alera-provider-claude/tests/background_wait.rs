mod support;

use alera_provider_protocol::{EventKind, Provider, ProviderError};
use serde_json::json;
use support::*;

#[tokio::test]
async fn background_commands_can_be_awaited_until_they_finish() {
    let (mut provider, _handle) = started_provider([
        initialize_response(),
        json!({"type":"system","subtype":"task_started","task_id":"agent","session_id":"native-session","task_type":"local_agent","description":"Explore"}),
        json!({"type":"system","subtype":"task_started","task_id":"bash","session_id":"native-session","task_type":"local_bash","description":"npm test"}),
        json!({"type":"system","subtype":"task_started","task_id":"inline","session_id":"native-session","task_type":"local_bash","is_backgrounded":false,"description":"ls"}),
        json!({"type":"system","subtype":"task_notification","task_id":"bash","session_id":"native-session","status":"completed"}),
    ])
    .await;
    let requested = ["bash", "agent", "inline", "missing"].map(String::from);
    let mut started = 0;
    while started < 3 {
        if provider.next_event().await.unwrap().unwrap().kind == EventKind::TaskStarted {
            started += 1;
        }
    }
    // Sub-agents are always awaited and a foreground command ends with its
    // turn, so only the background command matches.
    assert_eq!(
        provider
            .await_background_tasks(&requested, true)
            .await
            .unwrap(),
        vec!["bash".to_owned()]
    );
    assert_eq!(
        provider
            .await_background_tasks(&requested, false)
            .await
            .unwrap(),
        vec!["bash".to_owned()]
    );
    while provider.next_event().await.unwrap().unwrap().kind != EventKind::TaskCompleted {}
    assert!(provider
        .await_background_tasks(&requested, true)
        .await
        .unwrap()
        .is_empty());
    provider.close().await.unwrap();
    assert!(matches!(
        provider.await_background_tasks(&requested, true).await,
        Err(ProviderError::InvalidState(_))
    ));
}
