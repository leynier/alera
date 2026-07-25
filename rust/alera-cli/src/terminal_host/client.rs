use serde_json::Value;
use tokio::io::{AsyncBufReadExt as _, AsyncWriteExt as _, BufReader};
use tokio::net::TcpStream;
use tokio::sync::mpsc::{Receiver, Sender, UnboundedReceiver, UnboundedSender};

use crate::terminal_host::frame_codec::{encode_json_frame, encode_output_frame};
use crate::terminal_host::protocol::BINARY_FRAMES_ENABLED_EVENT;
use crate::terminal_host::server::ServerCommand;

/// One outbound item on a client's lane.
///
/// The upgrade travels in band rather than through a shared flag: the server
/// queues the hello response and then the upgrade on the same channel, so the
/// writer is guaranteed to emit the response as a line before switching. A
/// shared flag could flip before the response was written and frame it, while
/// the client was still reading lines.
#[derive(Debug, Clone)]
pub enum ClientFrame {
    Json(Value),
    Output { session_id: String, data: Vec<u8> },
    UpgradeToBinary,
}

impl From<Value> for ClientFrame {
    fn from(value: Value) -> Self {
        ClientFrame::Json(value)
    }
}

impl ClientFrame {
    /// The JSON this frame would be on a text-only transport, or None for the
    /// upgrade marker, which has no representation there.
    pub fn as_json(&self) -> Option<Value> {
        match self {
            ClientFrame::Json(value) => Some(value.clone()),
            ClientFrame::Output { session_id, data } => {
                Some(crate::terminal_host::protocol::event(
                    "output",
                    serde_json::json!({
                        "sessionId": session_id,
                        "dataBase64": crate::terminal_host::protocol::encode_bytes(data),
                    }),
                ))
            }
            ClientFrame::UpgradeToBinary => None,
        }
    }
}

/// The server's view of a connected client. Control traffic stays independent
/// from bounded terminal output so a terminal burst cannot drop RPC responses.
#[derive(Clone)]
pub struct ClientHandle {
    pub control_out: UnboundedSender<ClientFrame>,
    pub terminal_out: Sender<ClientFrame>,
}

#[cfg(test)]
impl ClientHandle {
    pub fn test_channels() -> (Self, UnboundedReceiver<ClientFrame>) {
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
    mut control_out_rx: UnboundedReceiver<ClientFrame>,
    mut terminal_out_rx: Receiver<ClientFrame>,
) {
    let (read_half, mut write_half) = stream.into_split();
    let mut lines = BufReader::new(read_half).lines();
    let mut binary = false;
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
                            if write_frame(&mut write_half, terminal_value, &mut binary)
                                .await
                                .is_err()
                            {
                                failed = true;
                                break;
                            }
                        }
                        if failed
                            || write_frame(&mut write_half, value, &mut binary)
                                .await
                                .is_err()
                        {
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
                        if write_frame(&mut write_half, value, &mut binary)
                            .await
                            .is_err()
                        {
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

/// Writes one outbound item, honouring the mode this connection is currently
/// in. `binary` flips only when an [`ClientFrame::UpgradeToBinary`] is reached
/// in the stream, which is what keeps the switch ordered against the hello
/// response.
async fn write_frame(
    write_half: &mut tokio::net::tcp::OwnedWriteHalf,
    frame: ClientFrame,
    binary: &mut bool,
) -> std::io::Result<()> {
    match frame {
        ClientFrame::UpgradeToBinary => {
            // A sentinel line, not a silent flag flip. The reader may live in
            // another isolate, so the switch has to be visible in the byte
            // stream itself: anything else races with the port round-trip.
            write_json_line(
                write_half,
                &crate::terminal_host::protocol::event(
                    BINARY_FRAMES_ENABLED_EVENT,
                    serde_json::json!({}),
                ),
            )
            .await?;
            *binary = true;
            Ok(())
        }
        ClientFrame::Json(value) if *binary => {
            let bytes = encode_json_frame(&value)?;
            write_half.write_all(&bytes).await
        }
        ClientFrame::Json(value) => write_json_line(write_half, &value).await,
        ClientFrame::Output { session_id, data } if *binary => {
            write_half
                .write_all(&encode_output_frame(&session_id, &data))
                .await
        }
        // A client that never negotiated the capability still gets the base64
        // JSON event it expects.
        other => match other.as_json() {
            Some(value) => write_json_line(write_half, &value).await,
            None => Ok(()),
        },
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

        terminal_tx
            .send(json!({"event": "output"}).into())
            .await
            .unwrap();
        control_tx.send(json!({"event": "exit"}).into()).unwrap();
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
