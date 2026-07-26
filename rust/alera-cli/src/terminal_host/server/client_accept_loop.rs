use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use tokio::net::TcpListener;
use tokio::sync::mpsc::{self, UnboundedSender};

use super::{
    connection_loop, ClientFrame, ClientHandle, ClientKind, ServerCommand,
    CLIENT_TERMINAL_OUT_QUEUE_CAPACITY,
};

/// Accept local clients and hand each one to its own connection loop.
pub(super) fn spawn_accept_loop(
    listener: TcpListener,
    inbox: UnboundedSender<ServerCommand>,
    next_client_id: Arc<AtomicU64>,
) {
    tokio::spawn(async move {
        while let Ok((stream, _)) = listener.accept().await {
            let _ = stream.set_nodelay(true);
            let id = next_client_id.fetch_add(1, Ordering::Relaxed);
            let (control_out_tx, control_out_rx) = mpsc::unbounded_channel::<ClientFrame>();
            let (terminal_out_tx, terminal_out_rx) =
                mpsc::channel::<ClientFrame>(CLIENT_TERMINAL_OUT_QUEUE_CAPACITY);
            // Register the client before its lines can arrive: the
            // ClientConnected command is enqueued before the connection loop
            // (and thus any ClientLine) starts.
            if inbox
                .send(ServerCommand::ClientConnected {
                    id,
                    handle: ClientHandle {
                        control_out: control_out_tx,
                        terminal_out: terminal_out_tx,
                    },
                    kind: ClientKind::Local,
                })
                .is_err()
            {
                break;
            }
            tokio::spawn(connection_loop(
                stream,
                id,
                inbox.clone(),
                control_out_rx,
                terminal_out_rx,
            ));
        }
    });
}
