use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc,
};

use futures_util::{stream::SplitSink, SinkExt as _, StreamExt as _};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::mpsc::{self, error::TryRecvError, Receiver, UnboundedReceiver, UnboundedSender};
use tokio::task::JoinHandle;
use tokio_tungstenite::{accept_async, tungstenite::Message};

use crate::terminal_host::client::{
    ClientFrame, ClientFrameOrdering, ClientHandle, MOBILE_CLIENT_TERMINAL_OUT_QUEUE_CAPACITY,
};
use crate::terminal_host::frame_codec::encode_output_payload;
use crate::terminal_host::server::{ClientKind, ServerCommand};

pub fn spawn_mobile_gateway_accept_loop(
    listener: TcpListener,
    inbox: UnboundedSender<ServerCommand>,
    next_client_id: Arc<AtomicU64>,
) -> JoinHandle<()> {
    tokio::spawn(async move {
        while let Ok((stream, _)) = listener.accept().await {
            let _ = stream.set_nodelay(true);
            let id = next_client_id.fetch_add(1, Ordering::Relaxed);
            let inbox = inbox.clone();
            tokio::spawn(async move {
                if let Err(error) = accept_mobile_connection(stream, id, inbox).await {
                    tracing::warn!("alera mobile gateway connection failed: {error}");
                }
            });
        }
    })
}

async fn accept_mobile_connection(
    stream: TcpStream,
    id: u64,
    inbox: UnboundedSender<ServerCommand>,
) -> anyhow::Result<()> {
    let socket = accept_async(stream).await?;
    let (control_out_tx, control_out_rx) = mpsc::unbounded_channel::<ClientFrame>();
    let (terminal_out_tx, terminal_out_rx) =
        mpsc::channel::<ClientFrame>(MOBILE_CLIENT_TERMINAL_OUT_QUEUE_CAPACITY);
    inbox.send(ServerCommand::ClientConnected {
        id,
        handle: ClientHandle::new(control_out_tx, terminal_out_tx),
        kind: ClientKind::Mobile,
    })?;
    mobile_websocket_loop(socket, id, inbox, control_out_rx, terminal_out_rx).await;
    Ok(())
}

async fn mobile_websocket_loop(
    socket: tokio_tungstenite::WebSocketStream<TcpStream>,
    id: u64,
    inbox: UnboundedSender<ServerCommand>,
    mut control_out_rx: UnboundedReceiver<ClientFrame>,
    mut terminal_out_rx: Receiver<ClientFrame>,
) {
    let (mut write, mut read) = socket.split();
    let mut binary = false;
    let mut ordering = ClientFrameOrdering::default();
    loop {
        if ordering.has_pending_terminal() {
            match control_out_rx.try_recv() {
                Ok(control) => {
                    if send_mobile_control_frame(
                        &mut write,
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
                    if send_mobile_value(&mut write, &frame, &mut binary)
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
            inbound = read.next() => {
                match inbound {
                    Some(Ok(Message::Text(text))) => {
                        if inbox.send(ServerCommand::ClientLine { id, line: text.to_string() }).is_err() {
                            break;
                        }
                    }
                    Some(Ok(Message::Binary(bytes))) => {
                        if let Ok(line) = String::from_utf8(bytes.to_vec()) {
                            if inbox.send(ServerCommand::ClientLine { id, line }).is_err() {
                                break;
                            }
                        }
                    }
                    Some(Ok(Message::Ping(payload))) => {
                        if write.send(Message::Pong(payload)).await.is_err() {
                            break;
                        }
                    }
                    Some(Ok(Message::Close(_))) | None => {
                        let _ = inbox.send(ServerCommand::ClientDisconnected { id });
                        break;
                    }
                    Some(Ok(_)) => {}
                    Some(Err(_)) => {
                        let _ = inbox.send(ServerCommand::ClientDisconnected { id });
                        break;
                    }
                }
            }
            outbound = control_out_rx.recv() => {
                match outbound {
                    Some(control) => {
                        if send_mobile_control_frame(
                            &mut write,
                            control,
                            &mut terminal_out_rx,
                            &mut ordering,
                            &mut binary,
                        )
                        .await
                        .is_err() {
                            let _ = inbox.send(ServerCommand::ClientDisconnected { id });
                            break;
                        }
                    }
                    None => break,
                }
            }
            outbound = terminal_out_rx.recv() => {
                match outbound {
                    Some(terminal) => {
                        ordering.stage_terminal(terminal);
                        let result = match control_out_rx.try_recv() {
                            Ok(control) => {
                                send_mobile_control_frame(
                                    &mut write,
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
                                send_mobile_value(&mut write, &frame, &mut binary).await
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

async fn send_mobile_control_frame(
    write: &mut SplitSink<tokio_tungstenite::WebSocketStream<TcpStream>, Message>,
    control: ClientFrame,
    terminal_out_rx: &mut Receiver<ClientFrame>,
    ordering: &mut ClientFrameOrdering,
    binary: &mut bool,
) -> anyhow::Result<()> {
    let (terminal, control) = ordering.before_control(control, terminal_out_rx);
    for frame in &terminal {
        send_mobile_value(write, frame, binary).await?;
    }
    send_mobile_value(write, &control, binary).await
}

/// Sends one frame over the WebSocket.
///
/// The WebSocket already delimits messages, so a device that negotiated binary
/// output just gets a `Message::Binary` with the session id and the raw bytes.
/// No length-prefixed framing is needed here, unlike the local TCP socket.
async fn send_mobile_value(
    write: &mut SplitSink<tokio_tungstenite::WebSocketStream<TcpStream>, Message>,
    frame: &ClientFrame,
    binary: &mut bool,
) -> anyhow::Result<()> {
    if let ClientFrame::UpgradeToBinary = frame {
        *binary = true;
        return Ok(());
    }
    if let ClientFrame::RestartRuntimeAfterWrite { inbox } = frame {
        let _ = inbox.send(ServerCommand::RequestedRestart);
        return Ok(());
    }
    if *binary {
        if let ClientFrame::Output { session_id, data } = frame {
            write
                .send(Message::Binary(
                    encode_output_payload(session_id, data).into(),
                ))
                .await?;
            return Ok(());
        }
    }
    let Some(value) = frame.as_json() else {
        return Ok(());
    };
    let text = serde_json::to_string(&value)?;
    write.send(Message::Text(text.into())).await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{json, Value};
    use tokio_tungstenite::connect_async;

    #[tokio::test]
    async fn control_response_stays_between_mobile_terminal_frames() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let address = listener.local_addr().unwrap();
        let (inbox, _inbox_rx) = mpsc::unbounded_channel();
        let (control_tx, control_rx) = mpsc::unbounded_channel();
        let (terminal_tx, terminal_rx) = mpsc::channel(MOBILE_CLIENT_TERMINAL_OUT_QUEUE_CAPACITY);
        let handle = ClientHandle::new(control_tx, terminal_tx);
        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let socket = accept_async(stream).await.unwrap();
            mobile_websocket_loop(socket, 1, inbox, control_rx, terminal_rx).await;
        });
        let (mut client, _) = connect_async(format!("ws://{address}")).await.unwrap();

        handle
            .try_send_terminal(json!({"event": "output-a"}).into())
            .unwrap();
        handle
            .send_control(json!({"response": "attachment"}).into())
            .unwrap();
        handle
            .try_send_terminal(json!({"event": "output-b"}).into())
            .unwrap();

        let mut frames = Vec::new();
        for _ in 0..3 {
            let message = client.next().await.unwrap().unwrap();
            let text = message.into_text().unwrap();
            frames.push(serde_json::from_str::<Value>(&text).unwrap());
        }
        assert_eq!(frames[0]["event"], json!("output-a"));
        assert_eq!(frames[1]["response"], json!("attachment"));
        assert_eq!(frames[2]["event"], json!("output-b"));

        drop(handle);
        server.await.unwrap();
    }
}
