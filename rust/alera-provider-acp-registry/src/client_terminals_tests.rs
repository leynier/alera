use crate::client_terminals::ClientTerminals;
use crate::{
    ClientTerminalChild, ClientTerminalCommand, ClientTerminalExitStatus, ClientTerminalSpawner,
    SpawnedClientTerminal,
};
use alera_provider_acp::agent_client_protocol::{AcpRequestId, RpcError, RpcRequest};
use alera_provider_acp::{AcpClientRequestHandler, AcpRequestHandlerContext};
use alera_provider_protocol::{
    ApprovalDecision, EventKind, ProviderEvent, ProviderKind, ProviderSession, RequestId,
    RequestKind, RuntimeRequest, RuntimeResponse, SessionStatus,
};
use async_trait::async_trait;
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::io::Cursor;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tokio::sync::watch;

#[derive(Default)]
pub(crate) struct FakeSpawner {
    pub(crate) commands: Mutex<Vec<ClientTerminalCommand>>,
    pub(crate) killed: Arc<AtomicUsize>,
    pub(crate) reaped: Arc<AtomicUsize>,
    pub(crate) immediate_exit: bool,
    pub(crate) stdout: Vec<u8>,
    pub(crate) stderr: Vec<u8>,
}

struct FakeChild {
    killed: Arc<AtomicUsize>,
    reaped: Arc<AtomicUsize>,
    stop: watch::Sender<bool>,
    stopped: watch::Receiver<bool>,
    immediate_exit: bool,
}

#[async_trait]
impl ClientTerminalChild for FakeChild {
    async fn wait(&mut self) -> Result<ClientTerminalExitStatus, String> {
        while !self.immediate_exit && !*self.stopped.borrow_and_update() {
            self.stopped
                .changed()
                .await
                .map_err(|error| error.to_string())?;
        }
        self.reaped.fetch_add(1, Ordering::SeqCst);
        Ok(ClientTerminalExitStatus {
            exit_code: if self.immediate_exit { Some(7) } else { None },
            signal: if self.immediate_exit {
                None
            } else {
                Some("SIGKILL".into())
            },
        })
    }

    fn terminate(&self) {
        if !*self.stop.borrow() {
            self.killed.fetch_add(1, Ordering::SeqCst);
            let _ = self.stop.send(true);
        }
    }
}

#[async_trait]
impl ClientTerminalSpawner for FakeSpawner {
    async fn spawn(&self, command: ClientTerminalCommand) -> Result<SpawnedClientTerminal, String> {
        self.commands.lock().unwrap().push(command);
        let (stop, stopped) = watch::channel(false);
        Ok(SpawnedClientTerminal {
            child: Box::new(FakeChild {
                killed: self.killed.clone(),
                reaped: self.reaped.clone(),
                stop,
                stopped,
                immediate_exit: self.immediate_exit,
            }),
            stdout: Box::pin(Cursor::new(self.stdout.clone())),
            stderr: Box::pin(Cursor::new(self.stderr.clone())),
        })
    }
}

pub(crate) fn session(turn: &str) -> ProviderSession {
    ProviderSession {
        provider: ProviderKind::Other("acpRegistry".into()),
        provider_instance_id: "instance".into(),
        thread_id: "app".into(),
        native_thread_id: "native".into(),
        status: SessionStatus::Running,
        model: None,
        cwd: None,
        active_turn_id: Some(turn.into()),
    }
}

pub(crate) fn service(spawner: Arc<FakeSpawner>) -> Arc<ClientTerminals> {
    let service = Arc::new(
        ClientTerminals::new(
            spawner,
            None,
            BTreeMap::from([("SHARED".into(), "config".into())]),
            64 * 1024 * 1024,
        )
        .unwrap(),
    );
    service.sync_session(&session("turn-1"));
    service
}

pub(crate) async fn call(
    service: &ClientTerminals,
    method: &str,
    params: Value,
) -> Result<Value, RpcError> {
    service
        .handle(
            RpcRequest {
                id: AcpRequestId::String("request".into()),
                method: method.into(),
                params,
                raw: Value::Null,
            },
            AcpRequestHandlerContext {
                request_id: AcpRequestId::String("request".into()),
                deadline: Instant::now() + Duration::from_secs(5),
            },
        )
        .await
        .expect("terminal request is handled")
}

pub(crate) fn approval(
    service: &ClientTerminals,
    decision: ApprovalDecision,
    kind: RequestKind,
    session_scope: bool,
) -> Result<(), alera_provider_protocol::ProviderError> {
    let request = RuntimeRequest {
        request_id: RequestId::Integer(9),
        thread_id: "app".into(),
        turn_id: Some("turn-1".into()),
        item_id: None,
        kind,
        questions: Vec::new(),
        payload: json!({"sessionId":"native", "options":[{"kind": if session_scope {"allow_always"} else {"allow_once"}, "optionId":"allow"}]}),
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
    let response = RuntimeResponse::Approval {
        request_id: RequestId::Integer(9),
        decision,
        updated_input: None,
    };
    service.validate_response(&response)?;
    service.record_response(&response);
    Ok(())
}

pub(crate) async fn create(service: &ClientTerminals) -> Result<String, RpcError> {
    call(
        service,
        "terminal/create",
        json!({"sessionId":"native", "command":"echo text"}),
    )
    .await
    .map(|value| value["terminalId"].as_str().unwrap().to_owned())
}

#[tokio::test]
async fn approvals_fail_closed_and_honor_only_supported_scope() {
    for decision in [ApprovalDecision::Decline, ApprovalDecision::Cancel] {
        let spawner = Arc::new(FakeSpawner::default());
        let service = service(spawner.clone());
        assert_eq!(create(&service).await.unwrap_err().code, -32002);
        approval(
            &service,
            decision,
            RequestKind::CommandExecutionApproval,
            false,
        )
        .unwrap();
        assert_eq!(create(&service).await.unwrap_err().code, -32002);
        assert!(spawner.commands.lock().unwrap().is_empty());
    }
    let spawner = Arc::new(FakeSpawner::default());
    let service = service(spawner.clone());
    approval(
        &service,
        ApprovalDecision::Accept,
        RequestKind::FileChangeApproval,
        false,
    )
    .unwrap();
    assert!(create(&service).await.is_err());
    assert!(approval(
        &service,
        ApprovalDecision::AcceptForSession,
        RequestKind::CommandExecutionApproval,
        false
    )
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
    service.sync_session(&session("turn-2"));
    assert!(create(&service).await.is_err());
    service.sync_session(&session("turn-1"));
    approval(
        &service,
        ApprovalDecision::AcceptForSession,
        RequestKind::CommandExecutionApproval,
        true,
    )
    .unwrap();
    service.sync_session(&session("turn-3"));
    create(&service).await.unwrap();
    service.interrupt();
    assert!(create(&service).await.is_err());
    service.close().await.unwrap();
    assert_eq!(spawner.reaped.load(Ordering::SeqCst), 2);
}

#[tokio::test]
async fn output_wait_release_and_session_isolation_preserve_native_output() {
    let spawner = Arc::new(FakeSpawner {
        immediate_exit: true,
        stdout: b"hello".to_vec(),
        stderr: b"error".to_vec(),
        ..Default::default()
    });
    let service = service(spawner.clone());
    approval(
        &service,
        ApprovalDecision::Accept,
        RequestKind::CommandExecutionApproval,
        false,
    )
    .unwrap();
    let id = create(&service).await.unwrap();
    let params = json!({"sessionId":"native", "terminalId":id});
    assert_eq!(
        call(&service, "terminal/wait_for_exit", params.clone())
            .await
            .unwrap(),
        json!({"exitCode":7, "signal":null})
    );
    let output = call(&service, "terminal/output", params.clone())
        .await
        .unwrap();
    assert!(output["output"].as_str().unwrap().contains("hello"));
    assert!(output["output"].as_str().unwrap().contains("error"));
    assert_eq!(output["exitStatus"]["exitCode"], 7);
    for method in [
        "terminal/output",
        "terminal/wait_for_exit",
        "terminal/kill",
        "terminal/release",
    ] {
        assert!(call(
            &service,
            method,
            json!({"sessionId":"foreign", "terminalId":id})
        )
        .await
        .is_err());
    }
    call(&service, "terminal/release", params.clone())
        .await
        .unwrap();
    assert!(call(&service, "terminal/output", params).await.is_err());
    let mut event = ProviderEvent::new(
        ProviderKind::Other("acpRegistry".into()),
        "instance",
        "app",
        EventKind::ItemUpdated,
        json!({"data":{"_meta":{"native":"preserved"},"content":[{"type":"terminal","terminalId":id}]}}),
        Some(alera_provider_protocol::RawEvent {
            source: "acp".into(),
            message_type: None,
            method: Some("session/update".into()),
            payload: json!({"params":{"sessionId":"native"}}),
        }),
    );
    service.observe(&mut event);
    assert_eq!(event.payload["itemType"], "command_execution");
    assert!(event.payload["detail"].as_str().unwrap().contains("hello"));
    assert_eq!(event.payload["data"]["_meta"]["native"], "preserved");
    service.close().await.unwrap();
}

#[tokio::test]
async fn wait_cancellation_does_not_drop_process_and_kill_reaps_it() {
    let spawner = Arc::new(FakeSpawner::default());
    let service = service(spawner.clone());
    approval(
        &service,
        ApprovalDecision::Accept,
        RequestKind::CommandExecutionApproval,
        false,
    )
    .unwrap();
    let id = create(&service).await.unwrap();
    let params = json!({"sessionId":"native", "terminalId":id});
    assert!(tokio::time::timeout(
        Duration::from_millis(20),
        call(&service, "terminal/wait_for_exit", params.clone())
    )
    .await
    .is_err());
    call(&service, "terminal/kill", params.clone())
        .await
        .unwrap();
    assert_eq!(
        call(&service, "terminal/wait_for_exit", params)
            .await
            .unwrap()["signal"],
        "SIGKILL"
    );
    assert_eq!(spawner.killed.load(Ordering::SeqCst), 1);
    assert_eq!(spawner.reaped.load(Ordering::SeqCst), 1);
    service.close().await.unwrap();
}

#[tokio::test]
async fn command_shell_environment_and_output_limit_are_explicit() {
    let spawner = Arc::new(FakeSpawner {
        immediate_exit: true,
        stdout: b"0123456789".to_vec(),
        ..Default::default()
    });
    let service = service(spawner.clone());
    approval(
        &service,
        ApprovalDecision::Accept,
        RequestKind::CommandExecutionApproval,
        false,
    )
    .unwrap();
    let result = call(&service, "terminal/create", json!({"sessionId":"native", "command":"program", "args":["literal | text"], "cwd":"child", "env":[{"name":"SHARED", "value":"request"}], "outputByteLimit":4})).await.unwrap();
    let params = json!({"sessionId":"native", "terminalId":result["terminalId"]});
    call(&service, "terminal/wait_for_exit", params.clone())
        .await
        .unwrap();
    let output = call(&service, "terminal/output", params).await.unwrap();
    assert_eq!(output["output"], "6789");
    assert_eq!(output["truncated"], true);
    {
        let commands = spawner.commands.lock().unwrap();
        assert!(!commands[0].shell);
        assert_eq!(commands[0].args, ["literal | text"]);
        assert!(commands[0].cwd.ends_with("child"));
        assert_eq!(
            commands[0].env[&std::ffi::OsString::from("SHARED")],
            "request"
        );
    }
    create(&service).await.unwrap();
    assert!(spawner.commands.lock().unwrap()[1].shell);
    service.close().await.unwrap();
}

#[tokio::test]
async fn live_and_unreleased_limits_are_enforced_before_spawn() {
    for immediate_exit in [false, true] {
        let spawner = Arc::new(FakeSpawner {
            immediate_exit,
            ..Default::default()
        });
        let service = service(spawner.clone());
        approval(
            &service,
            ApprovalDecision::Accept,
            RequestKind::CommandExecutionApproval,
            false,
        )
        .unwrap();
        let limit = if immediate_exit { 64 } else { 16 };
        for _ in 0..limit {
            let id = create(&service).await.unwrap();
            if immediate_exit {
                call(
                    &service,
                    "terminal/wait_for_exit",
                    json!({"sessionId":"native", "terminalId":id}),
                )
                .await
                .unwrap();
            }
        }
        assert_eq!(create(&service).await.unwrap_err().code, -32000);
        assert_eq!(spawner.commands.lock().unwrap().len(), limit);
        service.close().await.unwrap();
        assert_eq!(spawner.reaped.load(Ordering::SeqCst), limit);
    }
}
