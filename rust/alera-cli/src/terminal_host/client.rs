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
                        let queued_terminal_frames = terminal_out_rx.len();
                        let mut failed = false;
                        for _ in 0..queued_terminal_frames {
                            let Ok(terminal_value) = terminal_out_rx.try_recv() else {
                                break;
                            };
                            if write_json_line(&mut write_half, &terminal_value).await.is_err() {
                                failed = true;
                                break;
                            }
                        }
                        if failed || write_json_line(&mut write_half, &value).await.is_err() {
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
                        if write_json_line(&mut write_half, &value).await.is_err() {
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

async fn write_json_line(
    write_half: &mut tokio::net::tcp::OwnedWriteHalf,
    value: &Value,
) -> std::io::Result<()> {
    let mut bytes = serde_json::to_vec(value).map_err(std::io::Error::other)?;
    bytes.push(b'\n');
    write_half.write_all(&bytes).await
}

pub const CLIENT_TERMINAL_OUT_QUEUE_CAPACITY: usize = 8;

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use tokio::net::TcpListener;

    #[tokio::test]
    async fn queued_terminal_frames_keep_causal_order_before_control() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let address = listener.local_addr().unwrap();
        let client = TcpStream::connect(address).await.unwrap();
        let (server, _) = listener.accept().await.unwrap();
        let (inbox, _inbox_rx) = tokio::sync::mpsc::unbounded_channel();
        let (control_tx, control_rx) = tokio::sync::mpsc::unbounded_channel();
        let (terminal_tx, terminal_rx) =
            tokio::sync::mpsc::channel(CLIENT_TERMINAL_OUT_QUEUE_CAPACITY);

        terminal_tx.send(json!({"event": "output"})).await.unwrap();
        control_tx.send(json!({"event": "exit"})).unwrap();
        let task = tokio::spawn(connection_loop(server, 1, inbox, control_rx, terminal_rx));
        let mut lines = BufReader::new(client).lines();

        let first: Value =
            serde_json::from_str(&lines.next_line().await.unwrap().unwrap()).unwrap();
        let second: Value =
            serde_json::from_str(&lines.next_line().await.unwrap().unwrap()).unwrap();
        assert_eq!(first["event"], json!("output"));
        assert_eq!(second["event"], json!("exit"));

        drop(control_tx);
        drop(terminal_tx);
        task.await.unwrap();
    }
}
