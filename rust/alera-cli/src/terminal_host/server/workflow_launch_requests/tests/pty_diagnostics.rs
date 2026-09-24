use std::path::Path;
use std::time::Duration;

use tokio::sync::mpsc::UnboundedReceiver;

use crate::terminal_host::server::{ServerActor, ServerCommand};
use crate::terminal_host::session::{PtyEvent, PtyWriteCompletion};

pub(super) async fn assert_startup_command_executes(
    actor: &mut ServerActor,
    events: &mut UnboundedReceiver<ServerCommand>,
    session_id: &str,
    marker: &Path,
) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(30);
    let mut startup = false;
    let mut command_bytes = 0;
    let mut write_completed = false;
    let mut write_error = false;
    let mut pty_error = false;
    let mut child_exit = None;
    let mut cursor_reports = 0;
    let mut output_tail = Vec::new();
    let mut executed = false;
    while tokio::time::Instant::now() < deadline {
        if let Ok(Some(event)) =
            tokio::time::timeout(Duration::from_millis(50), events.recv()).await
        {
            let cursor_reports_to_answer = if let ServerCommand::Pty {
                event: PtyEvent::Output(data),
                ..
            } = &event
            {
                count_cursor_reports(&mut output_tail, data)
            } else {
                0
            };
            match &event {
                ServerCommand::TerminalStartupInput { command, .. } => {
                    startup = true;
                    command_bytes = command.len();
                }
                ServerCommand::Pty {
                    event:
                        PtyEvent::InputWritten {
                            completion: PtyWriteCompletion::StartupPlain { .. },
                            error,
                        },
                    ..
                } => {
                    write_completed = true;
                    write_error |= error.is_some();
                }
                ServerCommand::Pty {
                    event: PtyEvent::Error(_),
                    ..
                } => pty_error = true,
                ServerCommand::Pty {
                    event: PtyEvent::Exit(code),
                    ..
                } => child_exit = Some(*code),
                _ => {}
            }
            actor.handle(event).await;
            for _ in 0..cursor_reports_to_answer {
                cursor_reports += 1;
                actor
                    .sessions
                    .get_mut(session_id)
                    .unwrap()
                    .queue_write(PtyWriteCompletion::BestEffort, b"\x1b[1;1R")
                    .unwrap();
            }
        }
        executed = std::fs::read_to_string(marker)
            .is_ok_and(|content| content.contains("workflow-launch-test"));
        if startup && executed {
            break;
        }
    }
    let session = &actor.sessions[session_id];
    let output = session.buffer.to_bytes();
    let prefix = hex::encode(output.iter().take(4).copied().collect::<Vec<_>>());
    assert!(
        startup && executed,
        "the harmless command must execute (startup={startup}, command_bytes={command_bytes}, write_completed={write_completed}, write_error={write_error}, pty_error={pty_error}, child_exit={child_exit:?}, cursor_reports={cursor_reports}, running={}, marker_exists={}, terminal_bytes={}, output_prefix={prefix})",
        session.running(),
        marker.exists(),
        output.len()
    );
}

fn count_cursor_reports(tail: &mut Vec<u8>, data: &[u8]) -> usize {
    tail.extend_from_slice(data);
    let count = tail.windows(4).filter(|bytes| *bytes == b"\x1b[6n").count();
    let discard = tail.len().saturating_sub(3);
    tail.drain(..discard);
    count
}

#[test]
fn split_cursor_reports_are_answered_once_each() {
    let mut tail = Vec::new();
    assert_eq!(count_cursor_reports(&mut tail, b"text\x1b["), 0);
    assert_eq!(count_cursor_reports(&mut tail, b"6n"), 1);
    assert_eq!(count_cursor_reports(&mut tail, b"\x1b[6n\x1b[6n"), 2);
}
