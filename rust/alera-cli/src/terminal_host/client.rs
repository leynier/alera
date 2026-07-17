use serde_json::Value;
use tokio::io::{AsyncBufReadExt as _, AsyncWriteExt as _, BufReader};
use tokio::net::TcpStream;
use tokio::sync::mpsc::{Receiver, Sender, UnboundedSender};

use crate::terminal_host::server::ServerCommand;

/// The server's view of a connected client: an id plus a channel for outbound
/// frames (responses and broadcast events). Dropping the handle closes the
/// connection loop, which closes the socket.
#[derive(Clone)]
pub struct ClientHandle {
    pub out: Sender<Value>,
}

/// Drive one client connection: forward inbound newline-delimited JSON lines to
/// the server as commands, and write outbound frames received on `out_rx`.
///
/// The two directions are multiplexed in a single task so the server can close
/// a connection simply by dropping its [`ClientHandle`] (which ends `out_rx`).
pub async fn connection_loop(
    stream: TcpStream,
    id: u64,
    inbox: UnboundedSender<ServerCommand>,
    mut out_rx: Receiver<Value>,
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
            message = out_rx.recv() => {
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
        }
    }
}
pub const CLIENT_OUT_QUEUE_CAPACITY: usize = 8;
