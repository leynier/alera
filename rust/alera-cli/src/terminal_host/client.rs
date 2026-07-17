use serde_json::Value;
use tokio::io::{AsyncBufReadExt as _, AsyncWriteExt as _, BufReader};
use tokio::net::TcpStream;
use tokio::sync::mpsc::{Receiver, Sender, UnboundedReceiver, UnboundedSender};

use crate::terminal_host::server::ServerCommand;

/// The server's view of a connected client. Control traffic stays independent
/// from bounded terminal output so a terminal burst cannot drop RPC responses.
#[derive(Clone)]
pub struct ClientHandle {
    pub control_out: UnboundedSender<Value>,
    pub terminal_out: Sender<Value>,
}

#[cfg(test)]
impl ClientHandle {
    pub fn test_channels() -> (Self, UnboundedReceiver<Value>) {
        let (control_out, control_out_rx) = tokio::sync::mpsc::unbounded_channel();
        let (terminal_out, _terminal_out_rx) =
            tokio::sync::mpsc::channel(CLIENT_TERMINAL_OUT_QUEUE_CAPACITY);
        (
            Self {
                control_out,
                terminal_out,
            },
            control_out_rx,
        )
    }
}

/// Drive one client connection: forward inbound newline-delimited JSON lines to
/// the server as commands, and write outbound frames received on `out_rx`.
///
/// The two outbound lanes are serialized through this single writer. Dropping
/// the [`ClientHandle`] closes both lanes and therefore the socket.
pub async fn connection_loop(
    stream: TcpStream,
    id: u64,
    inbox: UnboundedSender<ServerCommand>,
    mut control_out_rx: UnboundedReceiver<Value>,
    mut terminal_out_rx: Receiver<Value>,
) {
    let (read_half, mut write_half) = stream.into_split();
    let mut lines = BufReader::new(read_half).lines();
    loop {
        tokio::select! {
            line = lines.next_line() => {
                match line {
                    Ok(Some(line)) => {
                        if inbox.send(ServerCommand::ClientLine { id, line }).is_err() {
                            break;
                        }
                    }
                    // EOF or read error: the client is gone.
                    _ => {
                        let _ = inbox.send(ServerCommand::ClientDisconnected { id });
                        break;
                    }
                }
            }
            message = control_out_rx.recv() => {
                match message {
                    Some(value) => {
                        let mut bytes = match serde_json::to_vec(&value) {
                            Ok(bytes) => bytes,
                            Err(_) => continue,
                        };
                        bytes.push(b'\n');
                        if write_half.write_all(&bytes).await.is_err() {
                            let _ = inbox.send(ServerCommand::ClientDisconnected { id });
                            break;
                        }
                    }
                    // The server dropped this client's handle.
                    None => break,
                }
            }
            message = terminal_out_rx.recv() => {
                match message {
                    Some(value) => {
                        let mut bytes = match serde_json::to_vec(&value) {
                            Ok(bytes) => bytes,
                            Err(_) => continue,
                        };
                        bytes.push(b'\n');
                        if write_half.write_all(&bytes).await.is_err() {
                            let _ = inbox.send(ServerCommand::ClientDisconnected { id });
                            break;
                        }
                    }
                    None => break,
                }
            }
        }
    }
}
pub const CLIENT_TERMINAL_OUT_QUEUE_CAPACITY: usize = 8;
