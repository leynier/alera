use alera_provider_codex::{CodexProvider, CodexProviderConfig, JsonTransport, MockTransport};
use alera_provider_protocol::{
    ApprovalDecision, Attachment, EventKind, InteractionMode, Provider, ProviderError, RequestId,
    RuntimeMode, RuntimeResponse, SessionStartInput, SessionStatus, TurnInput,
};
use async_trait::async_trait;
use serde_json::{json, Value};
use std::time::Duration;

fn initialize_response(id: i64) -> Value {
    json!({
        "id": id,
        "result": {
            "codexHome": "/tmp/codex",
            "platformFamily": "unix",
            "platformOs": "linux",
            "userAgent": "test",
        }
    })
}

fn thread_response(id: i64, native_id: &str) -> Value {
    json!({ "id": id, "result": { "thread": { "id": native_id } } })
}

fn config() -> CodexProviderConfig {
    CodexProviderConfig {
        instance_id: "codex-regression".into(),
        ..CodexProviderConfig::default()
    }
}

#[tokio::test]
async fn server_request_id_collision_keeps_logical_and_wire_ids_separate() {
    let transport = MockTransport::new([
        json!({
            "id": 1,
            "method": "item/commandExecution/requestApproval",
            "params": {
                "itemId": "logical-approval",
                "threadId": "native-collision",
                "turnId": "turn-collision"
            }
        }),
        initialize_response(1),
        thread_response(2, "native-collision"),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    provider
        .start_session(SessionStartInput::new("app-collision"))
        .await
        .unwrap();

    let event = provider.next_event().await.unwrap().unwrap();
    assert_eq!(event.kind, EventKind::RequestOpened);
    assert_eq!(event.request_id.as_deref(), Some("logical-approval"));
    assert_eq!(
        event.runtime_request.as_ref().unwrap().request_id,
        RequestId::String("logical-approval".into())
    );
    assert_eq!(
        event.provider_refs.as_ref().unwrap().provider_request_id,
        Some("logical-approval".into())
    );
    assert_eq!(event.raw.as_ref().unwrap().payload["id"], 1);

    provider
        .respond(RuntimeResponse::Approval {
            request_id: RequestId::String("logical-approval".into()),
            decision: ApprovalDecision::Accept,
            updated_input: None,
        })
        .await
        .unwrap();
    assert!(provider
        .transport()
        .writes()
        .iter()
        .any(|message| { message == &json!({ "id": 1, "result": { "decision": "accept" } }) }));
}

#[tokio::test]
async fn call_timeout_is_bounded() {
    let mut provider = CodexProvider::new(SlowTransport::default(), config());
    provider.config_mut().request_timeout = Duration::from_millis(2);
    let error = provider.initialize().await.unwrap_err();
    assert!(matches!(error, ProviderError::Timeout { operation } if operation == "initialize"));
}

#[tokio::test]
async fn runtime_mode_maps_exact_thread_and_turn_policy_shapes() {
    let transport = MockTransport::new([
        initialize_response(1),
        thread_response(2, "native-policy"),
        json!({ "id": 3, "result": { "turn": { "id": "native-turn-policy" } } }),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    let mut session_input = SessionStartInput::new("app-policy");
    session_input.model = Some("gpt-5".into());
    session_input.runtime_mode = RuntimeMode::FullAccess;
    provider.start_session(session_input).await.unwrap();
    provider
        .send_turn(TurnInput::text("app-policy", "run"))
        .await
        .unwrap();

    let writes = provider.transport().writes();
    assert_eq!(writes[2]["params"]["approvalPolicy"], "never");
    assert_eq!(writes[2]["params"]["sandbox"], "danger-full-access");
    assert_eq!(writes[2]["params"]["approvalsReviewer"], "user");
    assert_eq!(writes[3]["params"]["approvalPolicy"], "never");
    assert_eq!(writes[3]["params"]["approvalsReviewer"], "user");
    assert_eq!(
        writes[3]["params"]["sandboxPolicy"],
        json!({ "type": "dangerFullAccess" })
    );
}

#[tokio::test]
async fn plan_turn_includes_required_collaboration_settings() {
    let transport = MockTransport::new([
        initialize_response(1),
        thread_response(2, "native-plan"),
        json!({ "id": 3, "result": { "turn": { "id": "native-turn-plan" } } }),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    let mut session_input = SessionStartInput::new("app-plan");
    session_input.model = Some("gpt-5".into());
    provider.start_session(session_input).await.unwrap();
    let mut turn = TurnInput::text("app-plan", "plan");
    turn.interaction_mode = InteractionMode::Plan;
    provider.send_turn(turn).await.unwrap();
    assert_eq!(
        provider.transport().writes()[3]["params"]["collaborationMode"],
        json!({
            "mode": "plan",
            "settings": { "model": "gpt-5", "reasoning_effort": "medium" }
        })
    );
}

#[tokio::test]
async fn unsupported_file_attachment_fails_before_turn_start() {
    let transport = MockTransport::new([initialize_response(1), thread_response(2, "native-file")]);
    let mut provider = CodexProvider::new(transport, config());
    provider
        .start_session(SessionStartInput::new("app-file"))
        .await
        .unwrap();
    let mut turn = TurnInput::text("app-file", "attach");
    turn.attachments.push(Attachment::File {
        path: "/tmp/file.txt".into(),
    });
    assert!(matches!(
        provider.send_turn(turn).await,
        Err(ProviderError::Unsupported(_))
    ));
    assert_eq!(provider.transport().writes().len(), 3);
}

#[tokio::test]
async fn core_notifications_use_canonical_payload_shapes() {
    let transport = MockTransport::new([
        initialize_response(1),
        thread_response(2, "native-core"),
        json!({
            "method": "item/started",
            "params": {
                "threadId": "native-core",
                "turnId": "turn-core",
                "item": {
                    "id": "item-core",
                    "type": "commandExecution",
                    "status": "inProgress",
                    "command": "cargo test"
                }
            }
        }),
        json!({
            "method": "account/rateLimits/updated",
            "params": {
                "threadId": "native-core",
                "rateLimits": {
                    "limitId": "codex",
                    "primary": { "usedPercent": 50, "resetsAt": 1893456000 },
                    "secondary": { "usedPercent": 10 }
                }
            }
        }),
        json!({
            "method": "warning",
            "params": { "error": { "message": "provider warning" } }
        }),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    provider
        .start_session(SessionStartInput::new("app-core"))
        .await
        .unwrap();

    let item = provider.next_event().await.unwrap().unwrap();
    assert_eq!(item.kind, EventKind::ItemStarted);
    assert_eq!(item.item_id.as_deref(), Some("item-core"));
    assert_eq!(item.payload["itemType"], "command_execution");
    assert_eq!(item.payload["status"], "inProgress");
    item.validate().unwrap();

    let limits = provider.next_event().await.unwrap().unwrap();
    assert_eq!(limits.kind, EventKind::AccountRateLimitsUpdated);
    assert_eq!(limits.payload["limits"]["windows"][0]["kind"], "session");
    assert_eq!(limits.payload["limits"]["windows"][1]["kind"], "weekly");
    limits.validate().unwrap();

    let warning = provider.next_event().await.unwrap().unwrap();
    assert_eq!(warning.kind, EventKind::RuntimeWarning);
    assert_eq!(
        warning.payload,
        json!({ "message": "provider warning", "detail": { "message": "provider warning" } })
    );
    warning.validate().unwrap();
}

#[tokio::test]
async fn rate_window_kind_uses_explicit_duration_for_partial_snapshots() {
    let transport = MockTransport::new([
        initialize_response(1),
        thread_response(2, "native-rate-duration"),
        json!({
            "method": "account/rateLimits/updated",
            "params": {
                "threadId": "native-rate-duration",
                "rateLimits": {
                    "limitId": "codex",
                    "primary": { "usedPercent": 25, "windowDurationMins": 43200 }
                }
            }
        }),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    provider
        .start_session(SessionStartInput::new("app-rate-duration"))
        .await
        .unwrap();
    let event = provider.next_event().await.unwrap().unwrap();
    assert_eq!(event.kind, EventKind::AccountRateLimitsUpdated);
    assert_eq!(event.payload["limits"]["windows"][0]["kind"], "monthly");
    assert_eq!(
        event.payload["limits"]["windows"][0]["windowDurationMins"],
        43200
    );
    event.validate().unwrap();
}

#[tokio::test]
async fn malformed_delta_and_terminal_status_are_rejected_without_state_mutation() {
    let transport = MockTransport::new([
        initialize_response(1),
        thread_response(2, "native-malformed"),
        json!({
            "method": "item/agentMessage/delta",
            "params": { "threadId": "native-malformed", "turnId": "turn-1" }
        }),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    provider
        .start_session(SessionStartInput::new("app-malformed"))
        .await
        .unwrap();
    assert!(matches!(
        provider.next_event().await,
        Err(ProviderError::Protocol(message)) if message.contains("no string delta")
    ));
}

#[tokio::test]
async fn turn_completed_requires_a_known_native_status() {
    let transport = MockTransport::new([
        initialize_response(1),
        thread_response(2, "native-status"),
        json!({
            "method": "turn/completed",
            "params": {
                "threadId": "native-status",
                "turn": { "id": "turn-status" }
            }
        }),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    provider
        .start_session(SessionStartInput::new("app-status"))
        .await
        .unwrap();
    assert!(matches!(
        provider.next_event().await,
        Err(ProviderError::Protocol(message)) if message.contains("no status")
    ));
}

#[tokio::test]
async fn native_token_usage_is_normalized_to_shared_complete_shape() {
    let transport = MockTransport::new([
        initialize_response(1),
        thread_response(2, "native-usage"),
        json!({
            "method": "turn/completed",
            "params": {
                "threadId": "native-usage",
                "turn": {
                    "id": "turn-usage",
                    "status": "completed"
                },
                "tokenUsage": {
                    "last": {
                        "inputTokens": 10,
                        "cachedInputTokens": 2,
                        "outputTokens": 4,
                        "reasoningOutputTokens": 1
                    }
                }
            }
        }),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    provider
        .start_session(SessionStartInput::new("app-usage"))
        .await
        .unwrap();
    let event = provider.next_event().await.unwrap().unwrap();
    assert_eq!(event.payload["tokenUsage"]["usageStatus"], "complete");
    assert_eq!(event.payload["tokenUsage"]["usageScope"], "main_agent");
    assert_eq!(event.payload["tokenUsage"]["inputTokens"], 10);
    event.validate().unwrap();
}

#[tokio::test]
async fn failed_turn_maps_canonical_error_and_usage_details() {
    let transport = MockTransport::new([
        initialize_response(1),
        thread_response(2, "native-failed"),
        json!({
            "method": "turn/completed",
            "params": {
                "threadId": "native-failed",
                "turn": {
                    "id": "turn-failed",
                    "status": "failed",
                    "error": { "message": "model quota exceeded" },
                    "stopReason": "usage_limit"
                },
                "usage": { "input": 12 },
                "modelUsage": { "gpt-5": { "inputTokens": 12 } },
                "totalCostUsd": 0.25,
                "tokenUsage": {
                    "last": {
                        "inputTokens": 12,
                        "outputTokens": 0
                    }
                }
            }
        }),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    provider
        .start_session(SessionStartInput::new("app-failed"))
        .await
        .unwrap();
    let event = provider.next_event().await.unwrap().unwrap();
    assert_eq!(event.payload["state"], "failed");
    assert_eq!(event.payload["errorMessage"], "model quota exceeded");
    assert_eq!(event.payload["stopReason"], "usage_limit");
    assert_eq!(event.payload["usage"]["input"], 12);
    assert_eq!(event.payload["modelUsage"]["gpt-5"]["inputTokens"], 12);
    assert_eq!(event.payload["totalCostUsd"], 0.25);
    assert!(event.payload.get("error").is_none());
    assert_eq!(
        event.raw.as_ref().unwrap().payload["params"]["turn"]["error"]["message"],
        "model quota exceeded"
    );
    event.validate().unwrap();
}

#[tokio::test]
async fn typed_runtime_response_must_match_pending_request_kind() {
    let transport = MockTransport::new([
        initialize_response(1),
        thread_response(2, "native-kind"),
        json!({
            "id": 55,
            "method": "item/tool/requestUserInput",
            "params": {
                "itemId": "logical-input",
                "threadId": "native-kind",
                "turnId": "turn-kind",
                "questions": [{
                    "id": "choice",
                    "header": "Choice",
                    "question": "Choose"
                }]
            }
        }),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    provider
        .start_session(SessionStartInput::new("app-kind"))
        .await
        .unwrap();
    provider.next_event().await.unwrap().unwrap();
    let error = provider
        .respond(RuntimeResponse::Approval {
            request_id: RequestId::String("logical-input".into()),
            decision: ApprovalDecision::Accept,
            updated_input: None,
        })
        .await
        .unwrap_err();
    assert!(matches!(error, ProviderError::Validation(_)));
}

#[tokio::test]
async fn terminal_event_expires_pending_requests_and_rejects_stale_response() {
    let transport = MockTransport::new([
        initialize_response(1),
        thread_response(2, "native-terminal"),
        json!({
            "id": 90,
            "method": "item/commandExecution/requestApproval",
            "params": {
                "itemId": "stale-approval",
                "threadId": "native-terminal",
                "turnId": "turn-terminal"
            }
        }),
        json!({
            "method": "turn/completed",
            "params": {
                "threadId": "native-terminal",
                "turn": { "id": "turn-terminal", "status": "completed" }
            }
        }),
    ]);
    let mut provider = CodexProvider::new(transport, config());
    provider
        .start_session(SessionStartInput::new("app-terminal"))
        .await
        .unwrap();
    provider.next_event().await.unwrap().unwrap();
    let terminal = provider.next_event().await.unwrap().unwrap();
    assert_eq!(terminal.kind, EventKind::TurnCompleted);
    assert_eq!(provider.session().unwrap().status, SessionStatus::Ready);
    assert!(matches!(
        provider
            .respond(RuntimeResponse::Approval {
                request_id: RequestId::String("stale-approval".into()),
                decision: ApprovalDecision::Accept,
                updated_input: None,
            })
            .await,
        Err(ProviderError::InvalidState(_))
    ));
}

#[derive(Default)]
struct SlowTransport {
    writes: Vec<Value>,
}

#[async_trait]
impl JsonTransport for SlowTransport {
    async fn send(&mut self, message: Value) -> Result<(), alera_agent_transport::TransportError> {
        self.writes.push(message);
        Ok(())
    }

    async fn recv(&mut self) -> Result<Option<Value>, alera_agent_transport::TransportError> {
        tokio::time::sleep(Duration::from_millis(25)).await;
        Ok(None)
    }

    async fn close(&mut self) -> Result<(), alera_agent_transport::TransportError> {
        Ok(())
    }
}
