use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use futures_util::{SinkExt as _, StreamExt as _};
use tokio::sync::mpsc::{self, Receiver, UnboundedReceiver, UnboundedSender};
use tokio::sync::oneshot;
use tokio::task::JoinHandle;
use tokio_tungstenite::{
    connect_async,
    tungstenite::{
        client::IntoClientRequest,
        http::{header, HeaderValue, Request},
        Message,
    },
    MaybeTlsStream, WebSocketStream,
};

use crate::terminal_host::alera_account::{AleraAccountService, RelayGrant};
use crate::terminal_host::client::{
    ClientFrame, ClientFrameOrdering, ClientHandle, MOBILE_CLIENT_TERMINAL_OUT_QUEUE_CAPACITY,
};
use crate::terminal_host::frame_codec::encode_output_payload;

use super::relay_runtime_auth::{decode_fixed, decode_nonce, verify_grant};
use super::server::ServerCommand;
use super::{relay_crypto::IdentityKeyPair, relay_wire};

const MAX_MOBILE_CLIENTS: usize = 8;
const RETRY_DELAYS: [Duration; 6] = [
    Duration::from_secs(1),
    Duration::from_secs(2),
    Duration::from_secs(4),
    Duration::from_secs(8),
    Duration::from_secs(16),
    Duration::from_secs(30),
];

struct PendingPeer {
    client_id: String,
    receive: super::relay_crypto::RelaySession,
    send: super::relay_crypto::RelaySession,
}

struct ActivePeer {
    numeric_id: u64,
    receive: super::relay_crypto::RelaySession,
    writer: JoinHandle<()>,
}

struct RelayOutbound {
    client_id: String,
    payload: Vec<u8>,
}

type RelayWrite = futures_util::stream::SplitSink<
    WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>,
    Message,
>;

struct RelayInbound<'a> {
    identity: &'a IdentityKeyPair,
    runtime_grant: &'a RelayGrant,
    runtime_id: &'a str,
    inbox: &'a UnboundedSender<ServerCommand>,
    next_client_id: &'a AtomicU64,
    outbound_tx: &'a UnboundedSender<RelayOutbound>,
    write: &'a mut RelayWrite,
    pending: &'a mut HashMap<String, PendingPeer>,
    active: &'a mut HashMap<String, ActivePeer>,
}

pub fn spawn(
    service: Arc<AleraAccountService>,
    runtime_id: String,
    inbox: UnboundedSender<ServerCommand>,
    next_client_id: Arc<AtomicU64>,
) -> (JoinHandle<()>, oneshot::Sender<()>) {
    let (stop_tx, stop_rx) = oneshot::channel();
    let handle = tokio::spawn(run(service, runtime_id, inbox, next_client_id, stop_rx));
    (handle, stop_tx)
}

async fn run(
    service: Arc<AleraAccountService>,
    runtime_id: String,
    inbox: UnboundedSender<ServerCommand>,
    next_client_id: Arc<AtomicU64>,
    mut stop: oneshot::Receiver<()>,
) {
    let mut retry_index = 0_usize;
    loop {
        let result = connect_and_serve(
            &service,
            &runtime_id,
            inbox.clone(),
            next_client_id.clone(),
            &mut stop,
        )
        .await;
        let Err(error) = result else { return };
        let delay = RETRY_DELAYS[retry_index];
        retry_index = (retry_index + 1).min(RETRY_DELAYS.len() - 1);
        tracing::warn!(%error, "remote mobile relay disconnected; retrying in {:?}", delay);
        tokio::select! {
            _ = tokio::time::sleep(delay) => {}
            _ = &mut stop => return,
        }
    }
}

async fn connect_and_serve(
    service: &AleraAccountService,
    runtime_id: &str,
    inbox: UnboundedSender<ServerCommand>,
    next_client_id: Arc<AtomicU64>,
    stop: &mut oneshot::Receiver<()>,
) -> anyhow::Result<()> {
    let identity = service.relay_identity().await?;
    let grant = service.relay_grant().await?;
    if grant.client_kind != "runtime"
        || grant.client_id != runtime_id
        || grant.runtime_id != runtime_id
        || grant.expires_in <= 0
        || grant.client_key_version <= 0
        || grant.runtime_public_key.is_some()
        || grant.client_public_key != encoded(identity.public_bytes())
    {
        anyhow::bail!("cloud returned an invalid runtime relay grant");
    }
    let request = relay_request(&grant.relay_url, &grant.grant)?;
    let (socket, _) = connect_async(request).await?;
    let (mut write, mut read) = socket.split();
    let (outbound_tx, mut outbound_rx) = mpsc::unbounded_channel::<RelayOutbound>();
    let mut pending = HashMap::<String, PendingPeer>::new();
    let mut active = HashMap::<String, ActivePeer>::new();
    loop {
        tokio::select! {
            _ = &mut *stop => {
                dispose_peers(&mut active, &inbox).await;
                return Ok(());
            }
            outbound = outbound_rx.recv() => {
                let Some(outbound) = outbound else { return Ok(()); };
                write.send(Message::Binary(relay_wire::wrap(&outbound.client_id, &outbound.payload)?.into())).await?;
            }
            inbound = read.next() => {
                match inbound {
                    Some(Ok(Message::Binary(bytes))) => {
                        if let Err(error) = handle_inbound(&bytes, RelayInbound {
                            identity: &identity,
                            runtime_grant: &grant,
                            runtime_id,
                            inbox: &inbox,
                            next_client_id: &next_client_id,
                            outbound_tx: &outbound_tx,
                            write: &mut write,
                            pending: &mut pending,
                            active: &mut active,
                        }).await {
                            tracing::warn!(%error, "rejected a remote mobile relay frame");
                        }
                    }
                    Some(Ok(Message::Text(text))) => {
                        if let Err(error) = handle_inbound(text.as_bytes(), RelayInbound {
                            identity: &identity,
                            runtime_grant: &grant,
                            runtime_id,
                            inbox: &inbox,
                            next_client_id: &next_client_id,
                            outbound_tx: &outbound_tx,
                            write: &mut write,
                            pending: &mut pending,
                            active: &mut active,
                        }).await {
                            tracing::warn!(%error, "rejected a remote mobile relay frame");
                        }
                    }
                    Some(Ok(Message::Ping(payload))) => write.send(Message::Pong(payload)).await?,
                    Some(Ok(Message::Close(_))) | None => anyhow::bail!("relay websocket closed"),
                    Some(Ok(_)) => {}
                    Some(Err(error)) => return Err(error.into()),
                }
            }
        }
    }
}

fn relay_request(relay_url: &str, grant: &str) -> anyhow::Result<Request<()>> {
    let mut request = relay_url.into_client_request()?;
    request.headers_mut().insert(
        header::AUTHORIZATION,
        HeaderValue::from_str(&format!("Bearer {grant}"))?,
    );
    request.headers_mut().insert(
        header::ORIGIN,
        HeaderValue::from_static("https://app.alera.build"),
    );
    Ok(request)
}

async fn handle_inbound(frame: &[u8], context: RelayInbound<'_>) -> anyhow::Result<()> {
    let RelayInbound {
        identity,
        runtime_grant,
        runtime_id,
        inbox,
        next_client_id,
        outbound_tx,
        write,
        pending,
        active,
    } = context;
    let (client_id, payload) = relay_wire::unwrap(frame)?;
    if payload.is_empty() {
        pending.remove(&client_id);
        if let Some(peer) = active.remove(&client_id) {
            peer.writer.abort();
            let _ = inbox.send(ServerCommand::ClientDisconnected {
                id: peer.numeric_id,
            });
        }
        return Ok(());
    }
    if active.contains_key(&client_id) {
        let (numeric_id, opened) = {
            let peer = active
                .get_mut(&client_id)
                .expect("active relay peer exists");
            (peer.numeric_id, peer.receive.open(payload))
        };
        let plaintext = match opened {
            Ok(plaintext) => plaintext,
            Err(error) => {
                let peer = active.remove(&client_id).expect("active relay peer exists");
                peer.writer.abort();
                let _ = inbox.send(ServerCommand::ClientDisconnected {
                    id: peer.numeric_id,
                });
                return Err(anyhow::anyhow!(error));
            }
        };
        if let Ok(line) = String::from_utf8(plaintext) {
            inbox.send(ServerCommand::ClientLine {
                id: numeric_id,
                line,
            })?;
        }
        return Ok(());
    }
    if let Some(peer) = pending.remove(&client_id) {
        let confirmation: relay_wire::RelayConfirmation = relay_wire::decode_json(payload)?;
        if confirmation.version != relay_wire::RELAY_HELLO_VERSION {
            anyhow::bail!("unsupported relay confirmation version");
        }
        let confirmation = decode_fixed(&confirmation.confirmation)?;
        peer.receive
            .verify_peer_confirmation(&confirmation)
            .map_err(|error| anyhow::anyhow!(error))?;
        let client_numeric_id = next_client_id.fetch_add(1, Ordering::Relaxed);
        let (control_out_tx, control_out_rx) = mpsc::unbounded_channel();
        let (terminal_out_tx, terminal_out_rx) =
            mpsc::channel(MOBILE_CLIENT_TERMINAL_OUT_QUEUE_CAPACITY);
        let handle = ClientHandle::new(control_out_tx, terminal_out_tx);
        let writer = tokio::spawn(write_peer(
            client_numeric_id,
            client_id.clone(),
            peer.send,
            inbox.clone(),
            outbound_tx.clone(),
            control_out_rx,
            terminal_out_rx,
        ));
        inbox.send(ServerCommand::RelayClientConnected {
            id: client_numeric_id,
            handle,
            client_id: peer.client_id,
        })?;
        active.insert(
            client_id,
            ActivePeer {
                numeric_id: client_numeric_id,
                receive: peer.receive,
                writer,
            },
        );
        return Ok(());
    }
    if active.len() + pending.len() >= MAX_MOBILE_CLIENTS {
        anyhow::bail!("relay mobile connection limit reached");
    }
    let hello: relay_wire::RelayHello = relay_wire::decode_json(payload)?;
    let claims = verify_grant(&hello.grant).await?;
    if hello.version != relay_wire::RELAY_HELLO_VERSION
        || claims.aud != "alera-relay"
        || claims.role != "mobile"
        || claims.runtime_id != runtime_id
        || claims.client_id != client_id
        || hello.client_id != client_id
        || hello.runtime_id != runtime_id
        || hello.account_id != claims.account_id
        || claims.account_id != runtime_grant.account_id
        || hello.key_version != claims.key_version
        || hello.identity_public_key != claims.client_public_key
        || claims.runtime_public_key != encoded(identity.public_bytes())
    {
        anyhow::bail!("relay mobile grant is out of scope");
    }
    let client_static = decode_fixed(&hello.identity_public_key)?;
    let client_ephemeral = decode_fixed(&hello.ephemeral_public_key)?;
    let nonce = decode_nonce(&hello.nonce)?;
    let runtime_ephemeral = IdentityKeyPair::generate();
    let (receive, send) = relay_wire::derive_sessions(
        identity,
        &runtime_ephemeral,
        client_static,
        client_ephemeral,
        runtime_id,
        &client_id,
        &nonce,
    )
    .map_err(|error| anyhow::anyhow!(error))?;
    let confirmation = send.confirmation();
    let ack = relay_wire::RelayHelloAck {
        version: relay_wire::RELAY_HELLO_VERSION,
        runtime_id: runtime_id.to_owned(),
        client_id: client_id.clone(),
        identity_public_key: encoded(identity.public_bytes()),
        ephemeral_public_key: encoded(runtime_ephemeral.public_bytes()),
        nonce: encoded(nonce),
        confirmation: encoded(confirmation),
    };
    write
        .send(Message::Binary(
            relay_wire::wrap(&client_id, &relay_wire::encode_json(&ack)?)
                .unwrap()
                .into(),
        ))
        .await?;
    pending.insert(
        client_id,
        PendingPeer {
            client_id: claims.client_id,
            receive,
            send,
        },
    );
    Ok(())
}

async fn write_peer(
    numeric_id: u64,
    client_id: String,
    mut session: super::relay_crypto::RelaySession,
    inbox: UnboundedSender<ServerCommand>,
    outbound_tx: UnboundedSender<RelayOutbound>,
    mut control_rx: UnboundedReceiver<ClientFrame>,
    mut terminal_rx: Receiver<ClientFrame>,
) {
    let mut binary = false;
    let mut ordering = ClientFrameOrdering::default();
    loop {
        tokio::select! {
            control = control_rx.recv() => {
                let Some(control) = control else { break; };
                let mut output = PeerOutput {
                    terminal_rx: &mut terminal_rx,
                    ordering: &mut ordering,
                    binary: &mut binary,
                    outbound_tx: &outbound_tx,
                    inbox: &inbox,
                };
                if send_control(&mut session, &client_id, control, &mut output)
                    .await
                    .is_err()
                {
                    break;
                }
            }
            terminal = terminal_rx.recv() => {
                let Some(terminal) = terminal else { break; };
                ordering.stage_terminal(terminal);
                let frame = ordering.take_pending_terminal().expect("staged terminal frame");
                if send_frame(&mut session, &client_id, frame, &mut binary, &outbound_tx, &inbox).await.is_err() { break; }
            }
        }
    }
    let _ = inbox.send(ServerCommand::ClientDisconnected { id: numeric_id });
}

struct PeerOutput<'a> {
    terminal_rx: &'a mut Receiver<ClientFrame>,
    ordering: &'a mut ClientFrameOrdering,
    binary: &'a mut bool,
    outbound_tx: &'a UnboundedSender<RelayOutbound>,
    inbox: &'a UnboundedSender<ServerCommand>,
}

async fn send_control(
    session: &mut super::relay_crypto::RelaySession,
    client_id: &str,
    control: ClientFrame,
    output: &mut PeerOutput<'_>,
) -> anyhow::Result<()> {
    let (terminal, control) = output.ordering.before_control(control, output.terminal_rx);
    for frame in terminal {
        send_frame(
            session,
            client_id,
            frame,
            output.binary,
            output.outbound_tx,
            output.inbox,
        )
        .await?;
    }
    send_frame(
        session,
        client_id,
        control,
        output.binary,
        output.outbound_tx,
        output.inbox,
    )
    .await
}

async fn send_frame(
    session: &mut super::relay_crypto::RelaySession,
    client_id: &str,
    frame: ClientFrame,
    binary: &mut bool,
    outbound_tx: &UnboundedSender<RelayOutbound>,
    inbox: &UnboundedSender<ServerCommand>,
) -> anyhow::Result<()> {
    if matches!(frame, ClientFrame::UpgradeToBinary) {
        *binary = true;
        return Ok(());
    }
    if let ClientFrame::RestartRuntimeAfterWrite { .. } = frame {
        let _ = inbox.send(ServerCommand::RequestedRestart);
        return Ok(());
    }
    let payload = if *binary {
        if let ClientFrame::Output { session_id, data } = &frame {
            encode_output_payload(session_id, data)
        } else {
            serde_json::to_vec(&frame.as_json().unwrap_or_default())?
        }
    } else {
        let Some(value) = frame.as_json() else {
            return Ok(());
        };
        serde_json::to_vec(&value)?
    };
    let payload = session
        .seal(&payload)
        .map_err(|error| anyhow::anyhow!(error))?;
    outbound_tx
        .send(RelayOutbound {
            client_id: client_id.to_owned(),
            payload,
        })
        .map_err(|_| anyhow::anyhow!("relay writer is closed"))
}

async fn dispose_peers(
    active: &mut HashMap<String, ActivePeer>,
    inbox: &UnboundedSender<ServerCommand>,
) {
    for (_, peer) in active.drain() {
        peer.writer.abort();
        let _ = inbox.send(ServerCommand::ClientDisconnected {
            id: peer.numeric_id,
        });
    }
}

fn encoded(bytes: impl AsRef<[u8]>) -> String {
    URL_SAFE_NO_PAD.encode(bytes)
}

#[cfg(test)]
#[path = "relay_runtime_tests.rs"]
mod tests;
