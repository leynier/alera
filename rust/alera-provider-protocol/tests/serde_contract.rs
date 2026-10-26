use alera_provider_protocol::{
    ApprovalDecision, ApprovalPolicy, Attachment, EventKind, InteractionMode, ProviderEvent,
    ProviderKind, ProviderRefs, ProviderSession, RequestId, RuntimeMode, RuntimeRequest,
    RuntimeResponse, SandboxMode, SessionStartInput, SessionStatus, StreamKind, TurnInput,
    TurnStatus,
};
use serde_json::{json, Value};
use std::path::PathBuf;

#[test]
fn session_start_fixture_round_trips_camel_case_and_policy_names() {
    let fixture = json!({
        "threadId": "app-thread-1",
        "resumeThreadId": "native-thread-0",
        "cwd": "/workspace/project",
        "model": "gpt-5.6",
        "runtimeMode": "auto-accept-edits",
        "approvalPolicy": "on-request",
        "sandboxMode": "workspace-write",
        "options": { "reasoningEffort": "high" }
    });

    let input: SessionStartInput = serde_json::from_value(fixture.clone()).unwrap();
    assert_eq!(input.thread_id, "app-thread-1");
    assert_eq!(input.resume_thread_id.as_deref(), Some("native-thread-0"));
    assert_eq!(input.cwd, Some(PathBuf::from("/workspace/project")));
    assert_eq!(input.runtime_mode, RuntimeMode::AutoAcceptEdits);
    assert_eq!(input.approval_policy, Some(ApprovalPolicy::OnRequest));
    assert_eq!(input.sandbox_mode, Some(SandboxMode::WorkspaceWrite));
    input.validate().unwrap();
    assert_eq!(serde_json::to_value(input).unwrap(), fixture);
}

#[test]
fn provider_session_statuses_and_provider_names_keep_their_wire_values() {
    let statuses = [
        (SessionStatus::Starting, "starting"),
        (SessionStatus::Ready, "ready"),
        (SessionStatus::Running, "running"),
        (SessionStatus::Waiting, "waiting"),
        (SessionStatus::Stopped, "stopped"),
        (SessionStatus::Error, "error"),
    ];

    for (status, wire_status) in statuses {
        let session = ProviderSession {
            provider: ProviderKind::Claude,
            provider_instance_id: "claude-instance".into(),
            thread_id: "app-thread-1".into(),
            native_thread_id: "native-thread-1".into(),
            status,
            model: Some("claude-sonnet".into()),
            cwd: Some(PathBuf::from("/workspace/project")),
            active_turn_id: Some("turn-1".into()),
        };

        let wire = serde_json::to_value(&session).unwrap();
        assert_eq!(wire["provider"], "claudeAgent");
        assert_eq!(wire["status"], wire_status);
        assert_eq!(wire["activeTurnId"], "turn-1");
        assert_eq!(
            serde_json::from_value::<ProviderSession>(wire).unwrap(),
            session
        );
    }
}

#[test]
fn turn_fixture_round_trips_attachments_and_interaction_mode() {
    let fixture = json!({
        "threadId": "app-thread-1",
        "input": "Review these files",
        "attachments": [
            { "type": "image", "url": "https://example.test/screenshot.png" },
            { "type": "localImage", "path": "/workspace/screenshot.png" },
            { "type": "file", "path": "src/main.rs" }
        ],
        "model": "gpt-5.6",
        "interactionMode": "plan",
        "options": { "reasoningEffort": "medium" }
    });

    let input: TurnInput = serde_json::from_value(fixture.clone()).unwrap();
    assert_eq!(input.interaction_mode, InteractionMode::Plan);
    assert_eq!(input.attachments.len(), 3);
    input.validate().unwrap();
    assert_eq!(serde_json::to_value(input).unwrap(), fixture);
}

#[test]
fn approval_runtime_and_sandbox_policies_use_native_wire_values() {
    let approval_policies = [
        (ApprovalPolicy::Untrusted, "untrusted"),
        (ApprovalPolicy::OnFailure, "on-failure"),
        (ApprovalPolicy::OnRequest, "on-request"),
        (ApprovalPolicy::Never, "never"),
    ];
    for (policy, wire) in approval_policies {
        assert_eq!(serde_json::to_value(policy).unwrap(), json!(wire));
        assert_eq!(
            serde_json::from_value::<ApprovalPolicy>(json!(wire)).unwrap(),
            policy
        );
    }

    let runtime_modes = [
        (RuntimeMode::ApprovalRequired, "approval-required"),
        (RuntimeMode::AutoAcceptEdits, "auto-accept-edits"),
        (RuntimeMode::Auto, "auto"),
        (RuntimeMode::FullAccess, "full-access"),
    ];
    for (mode, wire) in runtime_modes {
        assert_eq!(serde_json::to_value(mode).unwrap(), json!(wire));
        assert_eq!(
            serde_json::from_value::<RuntimeMode>(json!(wire)).unwrap(),
            mode
        );
    }

    let sandbox_modes = [
        (SandboxMode::ReadOnly, "read-only"),
        (SandboxMode::WorkspaceWrite, "workspace-write"),
        (SandboxMode::DangerFullAccess, "danger-full-access"),
    ];
    for (mode, wire) in sandbox_modes {
        assert_eq!(serde_json::to_value(mode).unwrap(), json!(wire));
        assert_eq!(
            serde_json::from_value::<SandboxMode>(json!(wire)).unwrap(),
            mode
        );
    }
}

fn runtime_request_fixture(request_id: Value) -> Value {
    json!({
        "requestId": request_id,
        "threadId": "app-thread-1",
        "turnId": "turn-1",
        "itemId": "item-1",
        "kind": "command_execution_approval",
        "questions": [],
        "payload": { "command": "cargo test" }
    })
}

#[test]
fn request_id_preserves_string_and_integer_json_shapes() {
    let string_fixture = runtime_request_fixture(json!("codex-request-7"));
    let string_request: RuntimeRequest = serde_json::from_value(string_fixture.clone()).unwrap();
    assert_eq!(
        string_request.request_id,
        RequestId::String("codex-request-7".into())
    );
    assert_eq!(
        serde_json::to_value(string_request).unwrap(),
        string_fixture
    );

    let integer_fixture = runtime_request_fixture(json!(7));
    let integer_request: RuntimeRequest = serde_json::from_value(integer_fixture.clone()).unwrap();
    assert_eq!(integer_request.request_id, RequestId::Integer(7));
    assert_eq!(
        serde_json::to_value(integer_request).unwrap(),
        integer_fixture
    );

    assert!(serde_json::from_value::<RequestId>(json!(7.5)).is_err());
    assert!(serde_json::from_value::<RequestId>(Value::Null).is_err());
}

#[test]
fn approval_response_preserves_native_request_id_and_decision_wire_names() {
    let response = RuntimeResponse::Approval {
        request_id: RequestId::Integer(7),
        decision: ApprovalDecision::AcceptForSession,
        updated_input: Some(json!({ "command": "cargo test --locked" })),
        feedback: None,
    };
    let wire = serde_json::to_value(&response).unwrap();
    assert_eq!(wire["type"], "approval");
    assert_eq!(wire["requestId"], 7);
    assert_eq!(wire["decision"], "acceptForSession");
    assert_eq!(
        serde_json::from_value::<RuntimeResponse>(wire).unwrap(),
        response
    );

    for (decision, wire_name) in [
        (ApprovalDecision::Accept, "accept"),
        (ApprovalDecision::AcceptForSession, "acceptForSession"),
        (ApprovalDecision::AcceptAlways, "acceptAlways"),
        (ApprovalDecision::Decline, "decline"),
        (ApprovalDecision::Cancel, "cancel"),
    ] {
        assert_eq!(serde_json::to_value(decision).unwrap(), json!(wire_name));
    }
}

fn content_delta_fixture(kind: EventKind) -> Value {
    json!({
        "eventId": "00000000-0000-4000-8000-000000000001",
        "provider": "codex",
        "providerInstanceId": "codex-instance",
        "threadId": "00000000-0000-4000-8000-000000000002",
        "createdAt": "2026-10-12T12:34:56.000Z",
        "type": serde_json::to_value(kind).unwrap(),
        "turnId": "00000000-0000-4000-8000-000000000003",
        "itemId": "00000000-0000-4000-8000-000000000004",
        "requestId": "request-7",
        "providerRefs": {
            "providerTurnId": "native-turn-17",
            "providerItemId": "native-item-17",
            "providerRequestId": "native-request-17"
        },
        "payload": { "streamKind": "assistant_text", "delta": "hello" },
        "raw": {
            "source": "codex.app-server.notification",
            "method": "item/agentMessage/delta",
            "messageType": "notification",
            "payload": { "threadId": "native-thread-1", "delta": "hello" }
        }
    })
}

#[test]
fn event_envelope_retains_refs_raw_payload_and_known_kind() {
    let fixture = content_delta_fixture(EventKind::ContentDelta);
    let event: ProviderEvent = serde_json::from_value(fixture.clone()).unwrap();
    assert_eq!(event.provider, ProviderKind::Codex);
    assert_eq!(
        event.provider_refs,
        Some(ProviderRefs {
            provider_turn_id: Some("native-turn-17".into()),
            provider_item_id: Some("native-item-17".into()),
            provider_request_id: Some("native-request-17".into()),
        })
    );
    assert_eq!(
        event.raw.as_ref().unwrap().source,
        "codex.app-server.notification"
    );
    assert_eq!(event.raw.as_ref().unwrap().payload["delta"], "hello");
    event.validate().unwrap();
    assert_eq!(serde_json::to_value(event).unwrap(), fixture);
}

#[test]
fn unknown_event_kind_round_trips_the_original_wire_name() {
    let mut fixture = content_delta_fixture(EventKind::ContentDelta);
    fixture["type"] = json!("turn.future.v9");
    fixture["payload"] = json!({ "future": true });

    let event: ProviderEvent = serde_json::from_value(fixture.clone()).unwrap();
    assert_eq!(event.kind, EventKind::Unknown("turn.future.v9".into()));
    event.validate().unwrap();
    assert_eq!(serde_json::to_value(event).unwrap(), fixture);
}

#[test]
fn stream_and_turn_statuses_keep_provider_runtime_wire_names() {
    for (status, wire) in [
        (TurnStatus::Completed, "completed"),
        (TurnStatus::Failed, "failed"),
        (TurnStatus::Interrupted, "interrupted"),
        (TurnStatus::Cancelled, "cancelled"),
    ] {
        assert_eq!(serde_json::to_value(status).unwrap(), json!(wire));
    }

    for (kind, wire) in [
        (StreamKind::AssistantText, "assistant_text"),
        (StreamKind::ReasoningText, "reasoning_text"),
        (StreamKind::ReasoningSummaryText, "reasoning_summary_text"),
        (StreamKind::PlanText, "plan_text"),
        (StreamKind::CommandOutput, "command_output"),
        (StreamKind::FileChangeOutput, "file_change_output"),
        (StreamKind::Unknown, "unknown"),
    ] {
        assert_eq!(serde_json::to_value(kind).unwrap(), json!(wire));
    }
}

#[test]
fn attachment_only_turn_is_valid_for_image_or_file_context() {
    for attachment in [
        Attachment::Image {
            url: "https://example.test/image.png".into(),
        },
        Attachment::LocalImage {
            path: PathBuf::from("/workspace/image.png"),
        },
        Attachment::File {
            path: PathBuf::from("/workspace/notes.md"),
        },
    ] {
        let input = TurnInput {
            thread_id: "app-thread-1".into(),
            input: String::new(),
            attachments: vec![attachment],
            model: None,
            interaction_mode: InteractionMode::Default,
            options: Default::default(),
        };
        input.validate().unwrap();
    }
}
