use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc,
};

use futures_util::{stream::SplitSink, SinkExt as _, StreamExt as _};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::mpsc::{self, Receiver, UnboundedReceiver, UnboundedSender};
use tokio::task::JoinHandle;
use tokio_tungstenite::{accept_async, tungstenite::Message};

use crate::terminal_host::client::{
    ClientFrame, ClientHandle, MOBILE_CLIENT_TERMINAL_OUT_QUEUE_CAPACITY,
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
                    eprintln!("alera mobile gateway connection failed: {error}");
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
        handle: ClientHandle {
            control_out: control_out_tx,
            terminal_out: terminal_out_tx,
        },
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
    loop {
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
                    Some(value) => {
                        let queued_terminal_frames = terminal_out_rx.len();
                        let mut failed = false;
                        for _ in 0..queued_terminal_frames {
                            let Ok(terminal_value) = terminal_out_rx.try_recv() else {
                                break;
                            };
                            if send_mobile_value(&mut write, &terminal_value, &mut binary)
                                .await
                                .is_err() {
                                failed = true;
                                break;
                            }
                        }
                        if failed || send_mobile_value(&mut write, &value, &mut binary).await.is_err() {
                            let _ = inbox.send(ServerCommand::ClientDisconnected { id });
                            break;
                        }
                    }
                    None => break,
                }
            }
            outbound = terminal_out_rx.recv() => {
                match outbound {
                    Some(value) => {
                        if send_mobile_value(&mut write, &value, &mut binary).await.is_err() {
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
