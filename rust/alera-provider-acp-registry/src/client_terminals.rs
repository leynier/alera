use crate::client_terminals_lifecycle::{start_terminal, wait_for_exit};
use crate::client_terminals_output::TerminalOutputBuffer;
use crate::client_terminals_process::{
    ClientTerminalCommand, ClientTerminalExitStatus, ClientTerminalSpawner,
};
use crate::client_terminals_wire::{bound_response, wire_output};
use alera_provider_acp::agent_client_protocol::{AcpRequestId, RpcError, RpcRequest};
use alera_provider_acp::{AcpClientRequestHandler, AcpRequestHandlerContext};
use alera_provider_protocol::{ProviderError, RequestId, RuntimeRequest};
use async_trait::async_trait;
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::{BTreeMap, HashMap};
use std::ffi::OsString;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::sync::{watch, Mutex as AsyncMutex};

#[path = "client_terminals_policy.rs"]
mod policy;

const DEFAULT_OUTPUT_BYTE_LIMIT: usize = 4 * 1024 * 1024;
const MAX_OUTPUT_BYTE_LIMIT: usize = 8 * 1024 * 1024;
const MAX_LIVE_TERMINALS: usize = 16;
const MAX_UNRELEASED_TERMINALS: usize = 64;
const MAX_RETAINED_TERMINALS: usize = 32;
pub(crate) const MAX_RETAINED_OUTPUT_BYTES: usize = 16 * 1024 * 1024;

pub(crate) type TerminalExit = Result<ClientTerminalExitStatus, RpcError>;

pub(crate) struct TerminalRecord {
    pub(crate) session_id: String,
    pub(crate) buffer: TerminalOutputBuffer,
    pub(crate) exit: watch::Receiver<Option<TerminalExit>>,
    stop: watch::Sender<bool>,
    released: bool,
}

pub(crate) struct TerminalState {
    pub(crate) terminals: BTreeMap<String, TerminalRecord>,
    session_id: Option<String>,
    turn_id: Option<String>,
    turn_execute: Option<String>,
    session_execute: bool,
    cwd: PathBuf,
    closed: bool,
    next_id: u64,
    pending_approvals: HashMap<RequestId, RuntimeRequest>,
}

pub(crate) struct ClientTerminals {
    state: Arc<Mutex<TerminalState>>,
    creation: AsyncMutex<()>,
    spawner: Arc<dyn ClientTerminalSpawner>,
    env: BTreeMap<OsString, OsString>,
    max_response_frame_bytes: usize,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct CreateTerminalRequest {
    session_id: String,
    command: String,
    #[serde(default)]
    args: Vec<String>,
    cwd: Option<PathBuf>,
    #[serde(default)]
    env: Vec<EnvironmentVariable>,
    output_byte_limit: Option<usize>,
}

#[derive(Deserialize)]
struct EnvironmentVariable {
    name: String,
    value: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct TerminalRequest {
    session_id: String,
    terminal_id: String,
}

impl ClientTerminals {
    pub(crate) fn new(
        spawner: Arc<dyn ClientTerminalSpawner>,
        cwd: Option<PathBuf>,
        env: BTreeMap<OsString, OsString>,
        max_response_frame_bytes: usize,
    ) -> Result<Self, ProviderError> {
        if max_response_frame_bytes < 128 {
            return Err(ProviderError::Validation(
                "client terminals require a frame budget of at least 128 bytes".into(),
            ));
        }
        let cwd = match cwd {
            Some(cwd) => cwd,
            None => std::env::current_dir()
                .map_err(|error| ProviderError::InvalidState(error.to_string()))?,
        };
        Ok(Self {
            state: Arc::new(Mutex::new(TerminalState {
                terminals: BTreeMap::new(),
                session_id: None,
                turn_id: None,
                turn_execute: None,
                session_execute: false,
                cwd,
                closed: false,
                next_id: 1,
                pending_approvals: HashMap::new(),
            })),
            creation: AsyncMutex::new(()),
            spawner,
            env,
            max_response_frame_bytes,
        })
    }

    pub(crate) fn interrupt(&self) {
        let mut state = self.state.lock().expect("terminal state mutex poisoned");
        state.turn_id = None;
        state.turn_execute = None;
        state.pending_approvals.clear();
        for record in state.terminals.values() {
            let _ = record.stop.send(true);
        }
    }

    pub(crate) fn shutdown_now(&self) {
        self.interrupt();
        let mut state = self.state.lock().expect("terminal state mutex poisoned");
        state.closed = true;
        state.session_execute = false;
        state.session_id = None;
    }

    pub(crate) async fn close(&self) -> Result<(), ProviderError> {
        self.shutdown_now();
        // A spawn already authorized before close must finish handing its child to cleanup.
        let _permit = self.creation.lock().await;
        let exits = self
            .state
            .lock()
            .expect("terminal state mutex poisoned")
            .terminals
            .values()
            .map(|record| record.exit.clone())
            .collect::<Vec<_>>();
        let mut first_error = None;
        for exit in exits {
            if let Err(error) = wait_for_exit(exit).await {
                first_error.get_or_insert(ProviderError::InvalidState(error.message));
            }
        }
        self.state
            .lock()
            .expect("terminal state mutex poisoned")
            .terminals
            .clear();
        first_error.map_or(Ok(()), Err)
    }

    async fn create(&self, request: CreateTerminalRequest) -> Result<Value, RpcError> {
        let _permit = self.creation.lock().await;
        if request.command.trim().is_empty()
            || request.command.contains('\0')
            || request.args.iter().any(|arg| arg.contains('\0'))
        {
            return Err(request_error(
                -32602,
                "terminal command and args must be valid nonempty process input",
            ));
        }
        let mut env = self.env.clone();
        for variable in request.env {
            if variable.name.is_empty()
                || variable.name.contains(['=', '\0'])
                || variable.value.contains('\0')
            {
                return Err(request_error(
                    -32602,
                    "terminal environment variable is invalid",
                ));
            }
            env.insert(variable.name.into(), variable.value.into());
        }
        let (cwd, turn_id, terminal_id) = {
            let mut state = self.state.lock().expect("terminal state mutex poisoned");
            require_execution(&state, &request.session_id)?;
            if state
                .terminals
                .values()
                .filter(|record| !record.released)
                .count()
                >= MAX_UNRELEASED_TERMINALS
            {
                return Err(request_error(
                    -32000,
                    "terminal/create exceeded 64 unreleased terminals",
                ));
            }
            if state
                .terminals
                .values()
                .filter(|record| record.exit.borrow().is_none())
                .count()
                >= MAX_LIVE_TERMINALS
            {
                return Err(request_error(
                    -32000,
                    "terminal/create exceeded 16 live terminals",
                ));
            }
            let cwd = request.cwd.clone().map_or_else(
                || state.cwd.clone(),
                |cwd| {
                    if cwd.is_absolute() {
                        cwd
                    } else {
                        state.cwd.join(cwd)
                    }
                },
            );
            let id = state.next_id;
            state.next_id = id
                .checked_add(1)
                .ok_or_else(|| request_error(-32603, "terminal ID counter exhausted"))?;
            (
                cwd,
                state.turn_id.clone(),
                format!("client-terminal:{id:020}"),
            )
        };
        let spawned = self
            .spawner
            .spawn(ClientTerminalCommand {
                shell: request.args.is_empty(),
                command: request.command,
                args: request.args,
                cwd,
                env,
            })
            .await
            .map_err(|message| {
                request_error(
                    -32603,
                    &format!("could not start terminal command: {message}"),
                )
            })?;
        let failed_spawn = {
            let mut state = self.state.lock().expect("terminal state mutex poisoned");
            let expired = require_execution(&state, &request.session_id)
                .err()
                .or_else(|| {
                    (turn_id != state.turn_id).then(|| {
                        request_error(
                            -32002,
                            "terminal command approval expired before spawn completed",
                        )
                    })
                });
            let (stop, stop_receiver) = watch::channel(expired.is_some());
            let (exit_sender, exit) = watch::channel(None);
            let cleanup_exit = exit.clone();
            state.terminals.insert(
                terminal_id.clone(),
                TerminalRecord {
                    session_id: request.session_id,
                    buffer: TerminalOutputBuffer::new(
                        request
                            .output_byte_limit
                            .unwrap_or(DEFAULT_OUTPUT_BYTE_LIMIT)
                            .min(MAX_OUTPUT_BYTE_LIMIT),
                    ),
                    exit,
                    stop,
                    released: expired.is_some(),
                },
            );
            start_terminal(
                spawned,
                Arc::downgrade(&self.state),
                terminal_id.clone(),
                stop_receiver,
                exit_sender,
            );
            expired.map(|error| (error, cleanup_exit))
        };
        if let Some((error, exit)) = failed_spawn {
            let _ = wait_for_exit(exit).await;
            self.state
                .lock()
                .expect("terminal state mutex poisoned")
                .terminals
                .remove(&terminal_id);
            return Err(error);
        }
        Ok(json!({"terminalId":terminal_id}))
    }

    fn require_terminal(
        &self,
        request: &TerminalRequest,
    ) -> Result<watch::Receiver<Option<TerminalExit>>, RpcError> {
        let state = self.state.lock().expect("terminal state mutex poisoned");
        let record = state
            .terminals
            .get(&request.terminal_id)
            .filter(|record| {
                !record.released
                    && record.session_id == request.session_id
                    && state.session_id.as_deref() == Some(&request.session_id)
                    && !state.closed
            })
            .ok_or_else(|| request_error(-32602, "unknown terminal ID for this session"))?;
        Ok(record.exit.clone())
    }

    fn output(&self, request: &TerminalRequest, id: &AcpRequestId) -> Result<Value, RpcError> {
        self.require_terminal(request)?;
        let (text, truncated, exit) = {
            let state = self.state.lock().expect("terminal state mutex poisoned");
            let record = state
                .terminals
                .get(&request.terminal_id)
                .ok_or_else(|| request_error(-32602, "unknown terminal ID"))?;
            let exit = record.exit.borrow().clone();
            (record.buffer.text(), record.buffer.truncated, exit)
        };
        let exit_status = exit
            .transpose()?
            .map(|status| serde_json::to_value(status).expect("exit status is serializable"));
        wire_output(
            id,
            text,
            truncated,
            exit_status,
            self.max_response_frame_bytes,
        )
    }

    async fn stop(&self, request: &TerminalRequest, release: bool) -> Result<Value, RpcError> {
        let exit = self.require_terminal(request)?;
        {
            let mut state = self.state.lock().expect("terminal state mutex poisoned");
            let record = state
                .terminals
                .get_mut(&request.terminal_id)
                .ok_or_else(|| request_error(-32602, "unknown terminal ID"))?;
            record.released |= release;
            let _ = record.stop.send(true);
        }
        wait_for_exit(exit).await?;
        if release {
            let mut state = self.state.lock().expect("terminal state mutex poisoned");
            let released = state
                .terminals
                .iter()
                .filter(|(_, record)| record.released)
                .map(|(id, _)| id.clone())
                .collect::<Vec<_>>();
            for id in released
                .iter()
                .take(released.len().saturating_sub(MAX_RETAINED_TERMINALS))
            {
                state.terminals.remove(id);
            }
        }
        Ok(json!({}))
    }
}

#[async_trait]
impl AcpClientRequestHandler for ClientTerminals {
    fn supports_terminal(&self) -> bool {
        true
    }

    async fn handle(
        &self,
        request: RpcRequest,
        context: AcpRequestHandlerContext,
    ) -> Option<Result<Value, RpcError>> {
        if !matches!(
            request.method.as_str(),
            "terminal/create"
                | "terminal/output"
                | "terminal/wait_for_exit"
                | "terminal/kill"
                | "terminal/release"
        ) {
            return None;
        }
        let reserve = Duration::from_millis(10).min(context.remaining());
        let operation_deadline = context
            .deadline
            .checked_sub(reserve)
            .unwrap_or(context.deadline);
        let operation = async {
            if context.is_expired() {
                Err(request_error(-32001, "terminal request deadline expired"))
            } else if request.method == "terminal/create" {
                match serde_json::from_value(request.params) {
                    Ok(params) => self.create(params).await,
                    Err(error) => Err(request_error(-32602, &error.to_string())),
                }
            } else {
                match serde_json::from_value::<TerminalRequest>(request.params) {
                    Err(error) => Err(request_error(-32602, &error.to_string())),
                    Ok(params) => match request.method.as_str() {
                        "terminal/output" => self.output(&params, &request.id),
                        "terminal/wait_for_exit" => match self.require_terminal(&params) {
                            Ok(exit) => wait_for_exit(exit).await.map(|status| {
                                serde_json::to_value(status).expect("exit status is serializable")
                            }),
                            Err(error) => Err(error),
                        },
                        "terminal/kill" => self.stop(&params, false).await,
                        "terminal/release" => self.stop(&params, true).await,
                        _ => unreachable!(),
                    },
                }
            }
        };
        // Return a budgeted timeout before the shared client's outer deadline response.
        let result = match tokio::time::timeout_at(operation_deadline.into(), operation).await {
            Ok(result) => result,
            Err(_) => Err(request_error(-32001, "terminal request deadline expired")),
        };
        Some(bound_response(
            &request.id,
            result,
            self.max_response_frame_bytes,
        ))
    }
}

fn require_execution(state: &TerminalState, session_id: &str) -> Result<(), RpcError> {
    if state.closed || state.session_id.as_deref() != Some(session_id) || state.turn_id.is_none() {
        return Err(request_error(
            -32002,
            "terminal execution permission denied: no active session turn",
        ));
    }
    if !state.session_execute && state.turn_execute != state.turn_id {
        return Err(request_error(
            -32002,
            "terminal execution permission denied: command approval required",
        ));
    }
    Ok(())
}

pub(crate) fn request_error(code: i64, message: &str) -> RpcError {
    RpcError {
        code,
        message: message.into(),
        data: None,
    }
}
