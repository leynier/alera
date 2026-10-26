use alera_provider_protocol::*;
use serde_json::{json, Map};

#[test]
fn history_boundaries_are_typed_and_validate_native_references() {
    let fork = NativeForkInput {
        source_native_thread_id: "native-source".into(),
        session: SessionStartInput::new("app-target"),
        boundary: Some(NativeForkBoundary::Message("native-message-uuid".into())),
    };
    fork.validate().unwrap();
    let wire = serde_json::to_value(fork).unwrap();
    assert_eq!(
        wire["boundary"],
        json!({"type":"message","id":"native-message-uuid"})
    );
    let invalid = NativeRollbackInput {
        thread_id: "app".into(),
        boundary: NativeRollbackBoundary::RemoveTurns(0),
    };
    assert!(matches!(
        invalid.validate(),
        Err(ProviderError::Validation(_))
    ));
}

#[test]
fn canonical_effort_and_native_lineage_reject_invalid_values() {
    let mut options = Map::new();
    options.insert("reasoningEffort".into(), json!(7));
    assert!(matches!(
        reasoning_effort(&options),
        Err(ProviderError::Validation(_))
    ));
    options.insert("reasoningEffort".into(), json!("high"));
    assert_eq!(reasoning_effort(&options).unwrap(), Some("high"));
    assert!(NativeTask::default().validate().is_err());
    let mut event = ProviderEvent::new(
        ProviderKind::Claude,
        "instance",
        "app",
        EventKind::TaskStarted,
        json!({"taskId":"observed-task","nativeTask":{"nativeTaskId":"observed-task","childNativeThreadIds":[]}}),
        None,
    );
    event.validate().unwrap();
    assert_eq!(
        event
            .native_task()
            .unwrap()
            .unwrap()
            .native_task_id
            .as_deref(),
        Some("observed-task")
    );
    event.payload["nativeTask"]["childNativeThreadIds"] = json!([""]);
    assert!(event.validate().is_err());
}
