use std::sync::Arc;

use serde_json::Value;
use tokio::io::{AsyncBufReadExt as _, AsyncWriteExt as _, BufReader};
use tokio::net::TcpStream;
use tokio::sync::mpsc::{error::TryRecvError, Receiver, UnboundedReceiver, UnboundedSender};

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
    Budgeted {
        reservation: Arc<super::client_budget::FrameReservation>,
        frame: Box<ClientFrame>,
    },
    Json(Value),
    Output {
        session_id: String,
        data: Vec<u8>,
    },
    UpgradeToBinary,
    /// Re-enters the actor only after this connection has written every frame
    /// queued before the marker. Restart uses it so disposing the actor cannot
    /// drop the successful response the caller needs before reconnecting.
    RestartRuntimeAfterWrite {
        inbox: UnboundedSender<ServerCommand>,
    },
    /// Re-enters the actor only after this connection has written every frame
    /// queued before the marker. Shutdown uses it so the caller receives the
    /// successful response before disposal drops the connection.
    ShutdownRuntimeAfterWrite {
        inbox: UnboundedSender<ServerCommand>,
    },
    /// Control frames carry the last terminal sequence accepted before them.
    /// The writer uses it as a causal barrier between snapshot replies and
    /// output produced after that snapshot.
    OrderedControl {
        terminal_watermark: u64,
        frame: Box<ClientFrame>,
    },
    /// Terminal sequence numbers are internal to one connection and never
    /// appear on the wire.
    SequencedTerminal {
        sequence: u64,
        frame: Box<ClientFrame>,
    },
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
        match self.payload() {
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
            ClientFrame::UpgradeToBinary
            | ClientFrame::RestartRuntimeAfterWrite { .. }
            | ClientFrame::ShutdownRuntimeAfterWrite { .. } => None,
            ClientFrame::OrderedControl { .. }
            | ClientFrame::SequencedTerminal { .. }
            | ClientFrame::Budgeted { .. } => {
                unreachable!("payload strips internal ordering envelopes")
            }
        }
    }

    fn payload(&self) -> &ClientFrame {
        let mut frame = self;
        loop {
            frame = match frame {
                ClientFrame::OrderedControl { frame, .. }
                | ClientFrame::SequencedTerminal { frame, .. }
                | ClientFrame::Budgeted { frame, .. } => frame,
                _ => return frame,
            };
        }
    }

    fn into_control(self) -> (u64, ClientFrame) {
        match self {
            ClientFrame::OrderedControl {
                terminal_watermark,
                frame,
            } => (terminal_watermark, *frame),
            frame => (u64::MAX, frame),
        }
    }

    fn into_terminal(self) -> (u64, ClientFrame) {
        match self {
            ClientFrame::SequencedTerminal { sequence, frame } => (sequence, *frame),
            frame => (0, frame),
        }
    }
}

#[path = "client_handle.rs"]
mod handle;
pub use handle::ClientHandle;

#[derive(Default)]
pub(crate) struct ClientFrameOrdering {
    pending_terminal: Option<(u64, ClientFrame)>,
}

impl ClientFrameOrdering {
    pub(crate) fn stage_terminal(&mut self, frame: ClientFrame) {
        debug_assert!(self.pending_terminal.is_none());
        self.pending_terminal = Some(frame.into_terminal());
    }

    pub(crate) fn take_pending_terminal(&mut self) -> Option<ClientFrame> {
        self.pending_terminal.take().map(|(_, frame)| frame)
    }

    pub(crate) fn has_pending_terminal(&self) -> bool {
        self.pending_terminal.is_some()
    }

    pub(crate) fn before_control(
        &mut self,
        control: ClientFrame,
        terminal_out_rx: &mut Receiver<ClientFrame>,
    ) -> (Vec<ClientFrame>, ClientFrame) {
        let (terminal_watermark, control) = control.into_control();
        let mut terminal = Vec::new();
        loop {
            let next = self.pending_terminal.take().or_else(|| {
                terminal_out_rx
                    .try_recv()
                    .ok()
                    .map(ClientFrame::into_terminal)
            });
            let Some((sequence, frame)) = next else {
                break;
            };
            if sequence <= terminal_watermark {
                terminal.push(frame);
            } else {
                self.pending_terminal = Some((sequence, frame));
                break;
            }
        }
        (terminal, control)
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
    let mut ordering = ClientFrameOrdering::default();
    loop {
        if ordering.has_pending_terminal() {
            match control_out_rx.try_recv() {
                Ok(control) => {
                    if write_control_frame(
                        &mut write_half,
                        control,
                        &mut terminal_out_rx,
                        &mut ordering,
                        &mut binary,
                    )
                    .await
                    .is_err()
                    {
                        let _ = inbox.send(ServerCommand::ClientDisconnected { id });
                        break;
                    }
                    continue;
                }
                Err(TryRecvError::Empty) => {
                    let frame = ordering
                        .take_pending_terminal()
                        .expect("pending terminal frame just checked");
                    if write_frame(&mut write_half, frame, &mut binary)
                        .await
                        .is_err()
                    {
                        let _ = inbox.send(ServerCommand::ClientDisconnected { id });
                        break;
                    }
                    continue;
                }
                Err(TryRecvError::Disconnected) => break,
            }
        }
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
                    Some(control) => {
                        if write_control_frame(
                            &mut write_half,
                            control,
                            &mut terminal_out_rx,
                            &mut ordering,
                            &mut binary,
                        )
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
                    Some(terminal) => {
                        ordering.stage_terminal(terminal);
                        let result = match control_out_rx.try_recv() {
                            Ok(control) => {
                                write_control_frame(
                                    &mut write_half,
                                    control,
                                    &mut terminal_out_rx,
                                    &mut ordering,
                                    &mut binary,
                                )
                                .await
                            }
                            Err(TryRecvError::Empty) => {
                                let frame = ordering
                                    .take_pending_terminal()
                                    .expect("terminal frame was just staged");
                                write_frame(&mut write_half, frame, &mut binary).await
                            }
                            Err(TryRecvError::Disconnected) => break,
                        };
                        if result.is_err() {
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

async fn write_control_frame(
    write_half: &mut tokio::net::tcp::OwnedWriteHalf,
    control: ClientFrame,
    terminal_out_rx: &mut Receiver<ClientFrame>,
    ordering: &mut ClientFrameOrdering,
    binary: &mut bool,
) -> std::io::Result<()> {
    let (terminal, control) = ordering.before_control(control, terminal_out_rx);
    for frame in terminal {
        write_frame(write_half, frame, binary).await?;
    }
    write_frame(write_half, control, binary).await
}

/// Writes one outbound item, honouring the mode this connection is currently
/// in. `binary` flips only when an [`ClientFrame::UpgradeToBinary`] is reached
/// in the stream, which is what keeps the switch ordered against the hello
/// response.
async fn write_frame(
    write_half: &mut tokio::net::tcp::OwnedWriteHalf,
    mut frame: ClientFrame,
    binary: &mut bool,
) -> std::io::Result<()> {
    loop {
        frame = match frame {
            ClientFrame::OrderedControl { frame, .. }
            | ClientFrame::SequencedTerminal { frame, .. } => *frame,
            _ => break,
        };
    }
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
        ClientFrame::RestartRuntimeAfterWrite { inbox } => {
            let _ = inbox.send(ServerCommand::RequestedRestart);
            Ok(())
        }
        ClientFrame::ShutdownRuntimeAfterWrite { inbox } => {
            let _ = inbox.send(ServerCommand::RequestedShutdown);
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
        ClientFrame::OrderedControl { .. } | ClientFrame::SequencedTerminal { .. } => {
            unreachable!("ordering envelopes were stripped before writing")
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

/// The mobile gateway writes over a WAN socket where a single `send` can stall
/// for hundreds of milliseconds. The desktop lane's 8 frames is roughly 64 ms of
/// batches, so one stall fills it and parks the phone in the session's paused
/// set; 32 buys around 256 ms without letting the phone render a long tail of
/// stale output once a real stall ends.
pub const MOBILE_CLIENT_TERMINAL_OUT_QUEUE_CAPACITY: usize = 32;

const _: () = assert!(
    MOBILE_CLIENT_TERMINAL_OUT_QUEUE_CAPACITY > CLIENT_TERMINAL_OUT_QUEUE_CAPACITY,
    "the mobile lane exists to be deeper than the local desktop one"
);

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use tokio::net::TcpListener;

    #[tokio::test]
    async fn control_response_stays_between_its_causal_terminal_frames() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let address = listener.local_addr().unwrap();
        let client = TcpStream::connect(address).await.unwrap();
        let (server, _) = listener.accept().await.unwrap();
        let (inbox, _inbox_rx) = tokio::sync::mpsc::unbounded_channel();
        let (control_tx, control_rx) = tokio::sync::mpsc::unbounded_channel();
        let (terminal_tx, terminal_rx) =
            tokio::sync::mpsc::channel(CLIENT_TERMINAL_OUT_QUEUE_CAPACITY);
        let handle = ClientHandle::new(control_tx, terminal_tx);

        handle
            .try_send_terminal(json!({"event": "output-a"}).into())
            .unwrap();
        handle
            .send_control(json!({"response": "attachment"}).into())
            .unwrap();
        handle
            .try_send_terminal(json!({"event": "output-b"}).into())
            .unwrap();
        let task = tokio::spawn(connection_loop(server, 1, inbox, control_rx, terminal_rx));
        let mut lines = BufReader::new(client).lines();

        let first: Value =
            serde_json::from_str(&lines.next_line().await.unwrap().unwrap()).unwrap();
        let second: Value =
            serde_json::from_str(&lines.next_line().await.unwrap().unwrap()).unwrap();
        let third: Value =
            serde_json::from_str(&lines.next_line().await.unwrap().unwrap()).unwrap();
        assert_eq!(first["event"], json!("output-a"));
        assert_eq!(second["response"], json!("attachment"));
        assert_eq!(third["event"], json!("output-b"));

        drop(handle);
        task.await.unwrap();
    }
}
