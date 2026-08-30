use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;

use futures_util::{SinkExt as _, StreamExt as _};
use tokio::sync::mpsc::{self, Sender, UnboundedSender};
use tokio::sync::oneshot;
use tokio::task::JoinHandle;
use tokio_tungstenite::{connect_async, tungstenite::Message, MaybeTlsStream, WebSocketStream};

use crate::terminal_host::alera_account::{AleraAccountService, RelayGrant};
use crate::terminal_host::client::{
    ClientFrame, ClientFrameOrdering, ClientHandle, MOBILE_CLIENT_TERMINAL_OUT_QUEUE_CAPACITY,
};
use crate::terminal_host::frame_codec::encode_output_payload;

use super::relay_connection::{relay_request, RelayRetryBackoff};
use super::relay_runtime_auth::{decode_fixed, decode_nonce, encode, verify_grant};
use super::server::ServerCommand;
use super::{relay_crypto::IdentityKeyPair, relay_wire};

#[path = "relay_runtime_writer.rs"]
mod writer;
use writer::write_peer;

const MAX_MOBILE_CLIENTS: usize = 8;
const RELAY_PRESENCE_INTERVAL: Duration = Duration::from_secs(60);

struct PendingPeer {
    client_id: String,
    receive: super::relay_crypto::RelaySession,
    send: super::relay_crypto::RelaySession,
}

struct ActivePeer {
    numeric_id: u64,
    receive: super::relay_crypto::RelaySession,
    writer: JoinHandle<()>,
    inbox: UnboundedSender<ServerCommand>,
}

impl Drop for ActivePeer {
    fn drop(&mut self) {
        // A socket error or task cancellation must release the actor's sessions too.
        self.writer.abort();
        let _ = self.inbox.send(ServerCommand::ClientDisconnected {
            id: self.numeric_id,
        });
    }
}

struct RelayOutbound {
    numeric_id: u64,
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
    outbound_tx: &'a Sender<RelayOutbound>,
    write: &'a mut RelayWrite,
    pending: &'a mut HashMap<String, PendingPeer>,
    active: &'a mut HashMap<String, ActivePeer>,
    fragments: &'a mut HashMap<String, relay_wire::FragmentReassembler>,
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
    let mut retry_backoff = RelayRetryBackoff::default();
    loop {
        let result = connect_and_serve(
            &service,
            &runtime_id,
            inbox.clone(),
            next_client_id.clone(),
            &mut stop,
            &mut retry_backoff,
        )
        .await;
        let Err(error) = result else { return };
        let delay = retry_backoff.next_delay();
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
    retry_backoff: &mut RelayRetryBackoff,
) -> anyhow::Result<()> {
    let identity = service.relay_identity().await?;
    let grant = service.relay_grant().await?;
    if grant.client_kind != "runtime"
        || grant.client_id != runtime_id
        || grant.runtime_id != runtime_id
        || grant.expires_in <= 0
        || grant.client_key_version <= 0
        || grant.runtime_public_key.is_some()
        || grant.client_public_key != encode(identity.public_bytes())
    {
        anyhow::bail!("cloud returned an invalid runtime relay grant");
    }
    let request = relay_request(&grant.relay_url, &grant.grant)?;
    let (socket, _) = connect_async(request).await?;
    retry_backoff.reset();
    let (mut write, mut read) = socket.split();
    let (outbound_tx, mut outbound_rx) = mpsc::channel::<RelayOutbound>(64);
    let mut pending = HashMap::<String, PendingPeer>::new();
    let mut active = HashMap::<String, ActivePeer>::new();
    let mut fragments = HashMap::<String, relay_wire::FragmentReassembler>::new();
    let mut presence = tokio::time::interval(RELAY_PRESENCE_INTERVAL);
    let mut presence_refresh = futures_util::stream::FuturesUnordered::new();
    presence.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    presence.tick().await;
    // A grant expires even on an idle socket; renew before the edge refuses a phone.
    let renewal = tokio::time::sleep(Duration::from_secs(
        (grant.expires_in as u64).saturating_sub(5).max(1),
    ));
    tokio::pin!(renewal);
    let mut heartbeat = tokio::time::interval(Duration::from_secs(20));
    heartbeat.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    let mut last_received = tokio::time::Instant::now();
    loop {
        tokio::select! {
            _ = &mut renewal => anyhow::bail!("relay grant renewal is due"),
            _ = heartbeat.tick() => {
                if last_received.elapsed() >= Duration::from_secs(40) {
                    anyhow::bail!("relay heartbeat timed out");
                }
                send_message(&mut write, Message::Ping(Vec::new().into())).await?;
            }
            _ = &mut *stop => {
                return Ok(());
            }
            outbound = outbound_rx.recv() => {
                let Some(outbound) = outbound else { return Ok(()); };
                if active.get(&outbound.client_id).map(|peer| peer.numeric_id) != Some(outbound.numeric_id) {
                    continue;
                }
                for payload in relay_wire::fragment(&outbound.payload)? {
                    send_message(&mut write, Message::Binary(relay_wire::wrap(&outbound.client_id, &payload)?.into())).await?;
                }
            }
            _ = presence.tick() => {
                // Cloud latency must not stall terminal traffic on the relay socket.
                if presence_refresh.is_empty() {
                    presence_refresh.push(service.relay_identity());
                }
            }
            Some(result) = presence_refresh.next(), if !presence_refresh.is_empty() => {
                match result {
                    Ok(refreshed) if refreshed.public_bytes() != identity.public_bytes() => {
                        anyhow::bail!("relay identity rotated; reconnecting");
                    }
                    Ok(_) => {}
                    Err(error) => {
                        tracing::warn!(%error, "could not refresh remote mobile relay presence");
                    }
                }
            }
            inbound = read.next() => {
                last_received = tokio::time::Instant::now();
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
                            fragments: &mut fragments,
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
                            fragments: &mut fragments,
                        }).await {
                            tracing::warn!(%error, "rejected a remote mobile relay frame");
                        }
                    }
                    Some(Ok(Message::Ping(payload))) => send_message(&mut write, Message::Pong(payload)).await?,
                    Some(Ok(Message::Close(_))) | None => anyhow::bail!("relay websocket closed"),
                    Some(Ok(_)) => {}
                    Some(Err(error)) => return Err(error.into()),
                }
            }
        }
    }
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
        fragments,
    } = context;
    let (client_id, payload) = relay_wire::unwrap(frame)?;
    if payload.is_empty() {
        fragments.remove(&client_id);
        pending.remove(&client_id);
        active.remove(&client_id);
        return Ok(());
    }
    let Some(payload) = fragments
        .entry(client_id.clone())
        .or_default()
        .accept(payload)?
    else {
        return Ok(());
    };
    let payload = payload.as_slice();
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
                active.remove(&client_id);
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
                inbox: inbox.clone(),
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
        || claims.runtime_public_key != encode(identity.public_bytes())
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
        identity_public_key: encode(identity.public_bytes()),
        ephemeral_public_key: encode(runtime_ephemeral.public_bytes()),
        nonce: encode(nonce),
        confirmation: encode(confirmation),
    };
    send_message(
        write,
        Message::Binary(
            relay_wire::wrap(&client_id, &relay_wire::encode_json(&ack)?)
                .unwrap()
                .into(),
        ),
    )
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

async fn send_message(write: &mut RelayWrite, message: Message) -> anyhow::Result<()> {
    tokio::time::timeout(Duration::from_secs(5), write.send(message)).await??;
    Ok(())
}

#[cfg(test)]
#[path = "relay_runtime_tests.rs"]
mod tests;
