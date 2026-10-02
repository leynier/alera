use std::sync::atomic::{AtomicBool, Ordering};

use super::WorkspacePulseWatcherIdentity;

pub(super) fn report_watcher_failure(
    identity: &WorkspacePulseWatcherIdentity,
    failure_reported: &AtomicBool,
    inbox: &crate::terminal_host::ServerInbox,
    runtime_handle: Option<&tokio::runtime::Handle>,
    error: impl Into<String>,
) {
    if !failure_reported.swap(true, Ordering::Relaxed) {
        let command = super::super::ServerCommand::TerminalPulseWatcherFailed {
            workspace_id: identity.workspace_id.clone(),
            watcher_generation: identity.generation,
            error: error.into(),
        };
        if let Some(handle) = runtime_handle {
            let inbox = inbox.clone();
            handle.spawn(async move {
                let _ = inbox.send_wait(command).await;
            });
        } else if let Ok(handle) = tokio::runtime::Handle::try_current() {
            let inbox = inbox.clone();
            handle.spawn(async move {
                let _ = inbox.send_wait(command).await;
            });
        } else {
            let inbox = inbox.clone();
            let _ = std::thread::Builder::new()
                .name("terminal-pulse-failure-delivery".to_string())
                .spawn(move || {
                    let Ok(runtime) = tokio::runtime::Builder::new_current_thread()
                        .enable_all()
                        .build()
                    else {
                        return;
                    };
                    let _ = runtime.block_on(inbox.send_wait(command));
                });
        }
    }
}
