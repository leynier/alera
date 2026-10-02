use crate::terminal_host::session::PtyEvent;

use super::{ServerCommand, ServerInbox};

pub(super) fn forward_pty_event(inbox: &ServerInbox, session_id: &str, event: PtyEvent) {
    let (handled, handled_rx) = std::sync::mpsc::sync_channel(0);
    if inbox
        .send_blocking(ServerCommand::Pty {
            session_id: session_id.to_owned(),
            event,
            handled,
        })
        .is_ok()
    {
        let _ = handled_rx.recv();
    }
}
