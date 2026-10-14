use crate::client_terminals_tests::{approval, call, create, service, session, FakeSpawner};
use crate::{ClientTerminalCommand, ClientTerminalSpawner, SpawnedClientTerminal};
use alera_provider_acp::agent_client_protocol::{AcpRequestId, RpcRequest};
use alera_provider_acp::{AcpClientRequestHandler, AcpRequestHandlerContext};
use alera_provider_protocol::{
    ApprovalDecision, EventKind, ProviderEvent, ProviderKind, RequestId, RequestKind,
    RuntimeRequest, RuntimeResponse,
};
use async_trait::async_trait;
use serde_json::{json, Value};
use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::time::{Duration, Instant};

#[tokio::test]
async fn malformed_approval_cannot_grant_execution_and_turn_completion_expires_grants() {
    let service = service(Arc::new(FakeSpawner::default()));
    let request = RuntimeRequest {
        request_id: RequestId::Integer(1),
        thread_id: "app".into(),
        turn_id: Some("turn-1".into()),
        item_id: None,
        kind: RequestKind::CommandExecutionApproval,
        questions: Vec::new(),
        payload: json!({"sessionId":"native", "options":[{"kind":"allow_once", "optionId":""}]}),
    };
    let mut event = ProviderEvent::new(
        ProviderKind::Other("acpRegistry".into()),
        "instance",
        "app",
        EventKind::RequestOpened,
        json!({}),
        None,
    )
    .with_request(request);
    service.observe(&mut event);
    assert!(service
        .validate_response(&RuntimeResponse::Approval {
            request_id: RequestId::Integer(1),
            decision: ApprovalDecision::Accept,
            updated_input: None
        })
        .is_err());
    assert!(create(&service).await.is_err());
    approval(
        &service,
        ApprovalDecision::Accept,
        RequestKind::CommandExecutionApproval,
        false,
    )
    .unwrap();
    create(&service).await.unwrap();
    let mut completed = ProviderEvent::new(
        ProviderKind::Other("acpRegistry".into()),
        "instance",
        "app",
        EventKind::TurnCompleted,
        json!({"state":"completed"}),
        None,
    );
    service.observe(&mut completed);
    assert!(create(&service).await.is_err());
    service.sync_session(&session("turn-2"));
    assert!(create(&service).await.is_err());
    service.close().await.unwrap();
}

#[tokio::test]
async fn unrelated_and_expired_requests_do_not_spawn_processes() {
    let spawner = Arc::new(FakeSpawner::default());
    let service = service(spawner.clone());
    for method in ["future/request", "terminal/create"] {
        let result = service
            .handle(
                RpcRequest {
                    id: AcpRequestId::Number(1),
                    method: method.into(),
                    params: json!({"sessionId":"native", "command":"source"}),
                    raw: Value::Null,
                },
                AcpRequestHandlerContext {
                    request_id: AcpRequestId::Number(1),
                    deadline: Instant::now() - Duration::from_secs(1),
                },
            )
            .await;
        if method == "future/request" {
            assert!(result.is_none());
        } else {
            assert_eq!(result.unwrap().unwrap_err().code, -32001);
        }
    }
    assert!(spawner.commands.lock().unwrap().is_empty());
    service.close().await.unwrap();
}

#[tokio::test]
async fn dropping_terminal_service_stops_and_reaps_process_owner() {
    let spawner = Arc::new(FakeSpawner::default());
    let service = service(spawner.clone());
    approval(
        &service,
        ApprovalDecision::Accept,
        RequestKind::CommandExecutionApproval,
        false,
    )
    .unwrap();
    create(&service).await.unwrap();
    drop(service);
    tokio::time::timeout(Duration::from_secs(1), async {
        while spawner.reaped.load(Ordering::SeqCst) != 1 {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    assert_eq!(spawner.killed.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn per_terminal_and_aggregate_output_limits_keep_bounded_tail() {
    let spawner = Arc::new(FakeSpawner {
        immediate_exit: true,
        stdout: vec![b'x'; 8 * 1024 * 1024 + 4],
        ..Default::default()
    });
    let service = service(spawner);
    approval(
        &service,
        ApprovalDecision::Accept,
        RequestKind::CommandExecutionApproval,
        false,
    )
    .unwrap();
    let mut ids = Vec::new();
    for _ in 0..3 {
        let terminal = call(
            &service,
            "terminal/create",
            json!({"sessionId":"native", "command":"source", "outputByteLimit":64 * 1024 * 1024}),
        )
        .await
        .unwrap();
        let id = terminal["terminalId"].as_str().unwrap().to_owned();
        call(
            &service,
            "terminal/wait_for_exit",
            json!({"sessionId":"native", "terminalId":id}),
        )
        .await
        .unwrap();
        ids.push(id);
    }
    let mut total = 0;
    for id in ids {
        let output = call(
            &service,
            "terminal/output",
            json!({"sessionId":"native", "terminalId":id}),
        )
        .await
        .unwrap();
        let bytes = output["output"].as_str().unwrap().len();
        assert!(bytes <= 8 * 1024 * 1024);
        assert_eq!(output["truncated"], true);
        total += bytes;
    }
    assert_eq!(total, 16 * 1024 * 1024);
    service.close().await.unwrap();
}

struct DelayedSpawner {
    inner: Arc<FakeSpawner>,
    started: Arc<tokio::sync::Notify>,
    gate: tokio::sync::watch::Receiver<bool>,
}

#[async_trait]
impl ClientTerminalSpawner for DelayedSpawner {
    async fn spawn(&self, command: ClientTerminalCommand) -> Result<SpawnedClientTerminal, String> {
        self.started.notify_one();
        let mut gate = self.gate.clone();
        while !*gate.borrow_and_update() {
            gate.changed().await.map_err(|error| error.to_string())?;
        }
        self.inner.spawn(command).await
    }
}

#[tokio::test]
async fn closure_waits_for_in_flight_spawn_and_reaps_before_returning() {
    let inner = Arc::new(FakeSpawner::default());
    let started = Arc::new(tokio::sync::Notify::new());
    let (gate, gate_receiver) = tokio::sync::watch::channel(false);
    let service = Arc::new(
        crate::client_terminals::ClientTerminals::new(
            Arc::new(DelayedSpawner {
                inner: inner.clone(),
                started: started.clone(),
                gate: gate_receiver,
            }),
            None,
            Default::default(),
            1024 * 1024,
        )
        .unwrap(),
    );
    service.sync_session(&session("turn-1"));
    approval(
        &service,
        ApprovalDecision::Accept,
        RequestKind::CommandExecutionApproval,
        false,
    )
    .unwrap();
    let creating = service.clone();
    let create_task = tokio::spawn(async move { create(&creating).await });
    started.notified().await;
    service.shutdown_now();
    let closing = service.clone();
    let close_task = tokio::spawn(async move { closing.close().await });
    gate.send(true).unwrap();
    assert_eq!(create_task.await.unwrap().unwrap_err().code, -32002);
    close_task.await.unwrap().unwrap();
    assert_eq!(inner.reaped.load(Ordering::SeqCst), 1);
    assert_eq!(inner.killed.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn released_process_still_counts_as_live_until_reaped() {
    let spawner = Arc::new(FakeSpawner::default());
    let service = service(spawner.clone());
    approval(
        &service,
        ApprovalDecision::Accept,
        RequestKind::CommandExecutionApproval,
        false,
    )
    .unwrap();
    let mut ids = Vec::new();
    for _ in 0..16 {
        ids.push(create(&service).await.unwrap());
    }
    // Poll release through its pending wait without giving the process owner a turn.
    tokio::select! {
        biased;
        result = call(&service, "terminal/release", json!({"sessionId":"native", "terminalId":ids[0]})) => panic!("release must await the process owner: {result:?}"),
        () = std::future::ready(()) => {}
    }
    assert_eq!(create(&service).await.unwrap_err().code, -32000);
    assert_eq!(spawner.commands.lock().unwrap().len(), 16);
    service.close().await.unwrap();
    assert_eq!(spawner.reaped.load(Ordering::SeqCst), 16);
}

#[tokio::test]
async fn escaped_wire_preview_is_bounded_and_later_operations_stay_healthy() {
    let mut stdout = vec![0; 4096];
    stdout.extend_from_slice("😀tail".as_bytes());
    let spawner = Arc::new(FakeSpawner {
        immediate_exit: true,
        stdout,
        ..Default::default()
    });
    let service = Arc::new(
        crate::client_terminals::ClientTerminals::new(spawner, None, Default::default(), 256)
            .unwrap(),
    );
    service.sync_session(&session("turn-1"));
    approval(
        &service,
        ApprovalDecision::Accept,
        RequestKind::CommandExecutionApproval,
        false,
    )
    .unwrap();
    let id = create(&service).await.unwrap();
    let params = json!({"sessionId":"native", "terminalId":id});
    call(&service, "terminal/wait_for_exit", params.clone())
        .await
        .unwrap();
    let output = call(&service, "terminal/output", params.clone())
        .await
        .unwrap();
    assert_eq!(output["truncated"], true);
    assert!(output["output"].as_str().unwrap().ends_with("😀tail"));
    let frame = crate::client_terminals_wire::response_frame(
        &AcpRequestId::String("request".into()),
        &Ok(output),
    );
    assert!(serde_json::to_vec(&frame).unwrap().len() <= 256);
    call(&service, "terminal/output", params.clone())
        .await
        .unwrap();
    call(&service, "terminal/release", params).await.unwrap();
    create(&service).await.unwrap();
    service.close().await.unwrap();
}

#[test]
fn unusably_small_wire_budget_is_rejected_before_terminal_advertisement() {
    assert!(crate::client_terminals::ClientTerminals::new(
        Arc::new(FakeSpawner::default()),
        None,
        Default::default(),
        1
    )
    .is_err());
}

#[tokio::test]
async fn blocked_spawn_deadline_keeps_long_typed_id_response_within_wire_budget() {
    let spawner = Arc::new(FakeSpawner::default());
    let started = Arc::new(tokio::sync::Notify::new());
    let (gate, gate_receiver) = tokio::sync::watch::channel(false);
    let service = Arc::new(
        crate::client_terminals::ClientTerminals::new(
            Arc::new(DelayedSpawner {
                inner: spawner.clone(),
                started,
                gate: gate_receiver,
            }),
            None,
            Default::default(),
            512,
        )
        .unwrap(),
    );
    service.sync_session(&session("turn-1"));
    approval(
        &service,
        ApprovalDecision::Accept,
        RequestKind::CommandExecutionApproval,
        false,
    )
    .unwrap();
    let id = AcpRequestId::String("x".repeat(400));
    let params = json!({"sessionId":"native", "command":"x"});
    let raw =
        json!({"jsonrpc":"2.0", "id":id.as_value(), "method":"terminal/create", "params":params});
    assert!(serde_json::to_vec(&raw).unwrap().len() <= 512);
    let response = tokio::time::timeout(
        Duration::from_secs(1),
        service.handle(
            RpcRequest {
                id: id.clone(),
                method: "terminal/create".into(),
                params,
                raw,
            },
            AcpRequestHandlerContext {
                request_id: id.clone(),
                deadline: Instant::now() + Duration::from_millis(30),
            },
        ),
    )
    .await
    .unwrap()
    .unwrap();
    assert_eq!(response.as_ref().unwrap_err().code, -32001);
    let frame = crate::client_terminals_wire::response_frame(&id, &response);
    assert!(serde_json::to_vec(&frame).unwrap().len() <= 512);
    assert_eq!(frame["id"], id.as_value());
    assert!(spawner.commands.lock().unwrap().is_empty());
    gate.send(true).unwrap();
    create(&service).await.unwrap();
    assert_eq!(spawner.commands.lock().unwrap().len(), 1);
    service.close().await.unwrap();
}
