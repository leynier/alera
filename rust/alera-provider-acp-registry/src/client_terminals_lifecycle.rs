use crate::client_terminals::{request_error, TerminalExit, TerminalState};
use crate::client_terminals_output::append_output;
use crate::client_terminals_process::{
    ClientTerminalExitStatus, SpawnedClientTerminal, TerminalReadPipe,
};
use alera_provider_acp::agent_client_protocol::RpcError;
use std::sync::{Mutex, Weak};
use std::time::Duration;
use tokio::io::AsyncReadExt;
use tokio::sync::watch;

pub(crate) fn start_terminal(
    spawned: SpawnedClientTerminal,
    state: Weak<Mutex<TerminalState>>,
    terminal_id: String,
    mut stop: watch::Receiver<bool>,
    exit: watch::Sender<Option<TerminalExit>>,
) {
    tokio::spawn(async move {
        let SpawnedClientTerminal {
            mut child,
            stdout,
            stderr,
        } = spawned;
        let mut stdout = tokio::spawn(drain_pipe(stdout, state.clone(), terminal_id.clone()));
        let mut stderr = tokio::spawn(drain_pipe(stderr, state, terminal_id));
        let status = if *stop.borrow() {
            child.terminate();
            child.wait().await
        } else {
            tokio::select! {
                status = child.wait() => status,
                _ = stop.changed() => {
                    child.terminate();
                    child.wait().await
                }
            }
        };
        // Detached descendants can keep the pipes open after the direct child exits.
        let mut stdout_done = false;
        let mut stderr_done = false;
        let drains = tokio::time::timeout(Duration::from_secs(2), async {
            tokio::join!(
                async {
                    let _ = (&mut stdout).await;
                    stdout_done = true;
                },
                async {
                    let _ = (&mut stderr).await;
                    stderr_done = true;
                }
            );
        })
        .await;
        child.terminate();
        if drains.is_err() {
            if !stdout_done {
                stdout.abort();
                let _ = stdout.await;
            }
            if !stderr_done {
                stderr.abort();
                let _ = stderr.await;
            }
        }
        let status = status
            .map_err(|message| request_error(-32603, &format!("terminal wait failed: {message}")));
        let _ = exit.send(Some(status));
    });
}

async fn drain_pipe(
    mut pipe: TerminalReadPipe,
    state: Weak<Mutex<TerminalState>>,
    terminal_id: String,
) {
    let mut bytes = [0_u8; 16 * 1024];
    loop {
        match pipe.read(&mut bytes).await {
            Ok(0) | Err(_) => return,
            Ok(count) => {
                let Some(state) = state.upgrade() else {
                    return;
                };
                let mut state = state.lock().expect("terminal state mutex poisoned");
                append_output(&mut state, &terminal_id, &bytes[..count]);
            }
        }
    }
}

pub(crate) async fn wait_for_exit(
    mut exit: watch::Receiver<Option<TerminalExit>>,
) -> Result<ClientTerminalExitStatus, RpcError> {
    loop {
        if let Some(status) = exit.borrow_and_update().clone() {
            return status;
        }
        if exit.changed().await.is_err() {
            return Err(request_error(
                -32603,
                "terminal process owner closed without an exit status",
            ));
        }
    }
}
