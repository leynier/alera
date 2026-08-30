use super::relay_connection::{relay_request, RelayRetryBackoff, CONTROL_PROTOCOL};
use super::relay_runtime_auth::{encode, GrantVerifier};
use super::server::ServerCommand;
use super::{client_budget, relay_crypto, relay_runtime_auth, relay_wire};
use crate::terminal_host::alera_account::{AleraAccountService, RelayGrant};
use crate::terminal_host::client::{
    ClientFrame, ClientFrameOrdering, ClientHandle, MOBILE_CLIENT_TERMINAL_OUT_QUEUE_CAPACITY,
};
use crate::terminal_host::frame_codec::encode_output_payload;
use futures_util::StreamExt;
use relay_crypto::IdentityKeyPair;
use std::{
    collections::HashMap,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc,
    },
    time::Duration,
};
use tokio::sync::{
    mpsc::{self, Sender, UnboundedSender},
    oneshot, Semaphore,
};
use tokio::task::JoinHandle;
use tokio_tungstenite::{
    connect_async_with_config, tungstenite::Message, MaybeTlsStream, WebSocketStream,
};

#[path = "relay_failure.rs"]
mod failure;
use failure::RelayRejected;

#[path = "relay_runtime_peer.rs"]
mod peer;
#[path = "relay_socket_writer.rs"]
mod socket_writer;
#[path = "relay_runtime_writer.rs"]
mod writer;

const MAX_MOBILE_CLIENTS: usize = 8;
const RELAY_PRESENCE_INTERVAL: Duration = Duration::from_secs(60);
type RelayWrite = futures_util::stream::SplitSink<
    WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>,
    Message,
>;

struct SocketTask(JoinHandle<anyhow::Result<()>>);
impl Drop for SocketTask {
    fn drop(&mut self) {
        self.0.abort();
    }
}

trait RelayAccount: Send + Sync {
    fn relay_identity(
        &self,
    ) -> futures_util::future::BoxFuture<'_, anyhow::Result<IdentityKeyPair>>;
    fn relay_grant(&self) -> futures_util::future::BoxFuture<'_, anyhow::Result<RelayGrant>>;
}

impl RelayAccount for AleraAccountService {
    fn relay_identity(
        &self,
    ) -> futures_util::future::BoxFuture<'_, anyhow::Result<IdentityKeyPair>> {
        Box::pin(AleraAccountService::relay_identity(self))
    }
    fn relay_grant(&self) -> futures_util::future::BoxFuture<'_, anyhow::Result<RelayGrant>> {
        Box::pin(AleraAccountService::relay_grant(self))
    }
}

pub fn spawn(
    service: Arc<AleraAccountService>,
    runtime_id: String,
    inbox: UnboundedSender<ServerCommand>,
    next_client_id: Arc<AtomicU64>,
    generation: u64,
) -> (JoinHandle<()>, oneshot::Sender<()>) {
    let (stop_tx, stop_rx) = oneshot::channel();
    (
        tokio::spawn(run(
            service,
            runtime_id,
            inbox,
            next_client_id,
            stop_rx,
            generation,
        )),
        stop_tx,
    )
}

async fn run(
    service: Arc<AleraAccountService>,
    runtime_id: String,
    inbox: UnboundedSender<ServerCommand>,
    next_client_id: Arc<AtomicU64>,
    mut stop: oneshot::Receiver<()>,
    generation: u64,
) {
    let Ok(verifier) = GrantVerifier::new() else {
        report(
            &inbox,
            generation,
            "blocked",
            Some("configuration_invalid"),
            None,
        );
        return;
    };
    let mut backoff = RelayRetryBackoff::default();
    loop {
        report(&inbox, generation, "connecting", None, None);
        let result = tokio::select! {
            _ = &mut stop => return,
            result = connect_and_serve(service.as_ref(), &runtime_id, &inbox, &next_client_id, &verifier, &mut backoff, generation) => result,
        };
        let Err(error) = result else {
            return;
        };
        let mut delay = backoff.next_delay();
        let (cause, retryable, retry_after) = failure::retry_policy(&error);
        if !retryable {
            report(&inbox, generation, "blocked", Some(cause), None);
            return;
        }
        if let Some(retry) = retry_after {
            delay = delay.max(retry);
        }
        tracing::warn!(
            retry_ms = delay.as_millis(),
            cause,
            "remote relay disconnected; retry scheduled"
        );
        report(&inbox, generation, "retrying", Some(cause), Some(delay));
        tokio::select! { _ = tokio::time::sleep(delay) => {}, _ = &mut stop => return }
    }
}

async fn connect_and_serve(
    service: &dyn RelayAccount,
    runtime_id: &str,
    inbox: &UnboundedSender<ServerCommand>,
    next_id: &Arc<AtomicU64>,
    verifier: &GrantVerifier,
    backoff: &mut RelayRetryBackoff,
    generation: u64,
) -> anyhow::Result<()> {
    let established = tokio::time::timeout(Duration::from_secs(30), async {
        let identity = Arc::new(service.relay_identity().await?);
        let grant = service.relay_grant().await?;
        validate_runtime_grant(&grant, &identity, runtime_id)?;
        let (socket, response) = connect_async_with_config(
            relay_request(&grant.relay_url, &grant.grant)?,
            Some(
                tokio_tungstenite::tungstenite::protocol::WebSocketConfig::default()
                    .max_message_size(Some(1024 * 1024 + 130))
                    .max_frame_size(Some(1024 * 1024 + 130)),
            ),
            false,
        )
        .await?;
        Ok::<_, anyhow::Error>((identity, grant, socket, response))
    })
    .await??;
    let (identity, mut grant, socket, response) = established;
    report(inbox, generation, "connected", None, None);
    let negotiated = response
        .headers()
        .get("sec-websocket-protocol")
        .and_then(|value| value.to_str().ok())
        == Some(CONTROL_PROTOCOL);
    let (write, mut read) = socket.split();
    let (output, frames) = mpsc::channel(16);
    let (control, control_rx) = mpsc::channel(16);
    let mut writer = SocketTask(tokio::spawn(socket_writer::run(write, frames, control_rx)));
    let mut peers = HashMap::<String, peer::Peer>::new();
    let budget = Arc::new(Semaphore::new(client_budget::RELAY_RUNTIME_BYTES));
    let mut renewals = futures_util::stream::FuturesUnordered::new();
    let mut expiry = grant_expiry(&grant)?;
    let mut renew_at = expiry - if negotiated { 30 } else { 5 };
    let mut pending_renewal: Option<(u64, RelayGrant)> = None;
    let mut renewal_id = 0_u64;
    let mut tick = tokio::time::interval(Duration::from_secs(1));
    tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    let connected_at = tokio::time::Instant::now();
    let mut healthy = false;
    let mut last_received = tokio::time::Instant::now();
    let mut last_activity_report = tokio::time::Instant::now();
    let mut last_ping = tokio::time::Instant::now();
    let mut presence = tokio::time::interval(RELAY_PRESENCE_INTERVAL);
    presence.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    presence.tick().await;
    let mut refreshes = futures_util::stream::FuturesUnordered::new();
    loop {
        tokio::select! {
            result = &mut writer.0 => { result??; anyhow::bail!("relay writer closed"); }
            _ = tick.tick() => {
                let now = chrono::Utc::now().timestamp();
                let retired = peers.iter().filter(|(_, peer)| peer.task.is_finished() || !peer.lifetime.valid() || peer.budget.is_exhausted()).map(|(id, peer)| (id.clone(), peer.lifetime.close_code.load(Ordering::Acquire), peer.lifetime.connection_id.lock().unwrap().clone())).collect::<Vec<_>>();
                for (id, code, connection_id) in retired {
                    peers.remove(&id);
                    if negotiated && connection_id.is_some() {
                        let mut bytes = vec![0, 0];
                        bytes.extend(serde_json::to_vec(&serde_json::json!({ "type": "peer.close", "clientId": id, "code": code, "connectionId": connection_id }))?);
                        control.try_send(Message::Binary(bytes.into()))?;
                    }
                }
                if now >= expiry { anyhow::bail!("relay authorization expired"); }
                if !healthy && connected_at.elapsed() >= Duration::from_secs(30) { backoff.reset(); healthy = true; }
                if last_received.elapsed() >= Duration::from_secs(40) { anyhow::bail!("relay heartbeat timed out"); }
                if last_ping.elapsed() >= Duration::from_secs(20) {
                    control.try_send(Message::Ping(Vec::new().into()))?;
                    last_ping = tokio::time::Instant::now();
                }
                if now >= renew_at && renewals.is_empty() && pending_renewal.is_none() {
                    if !negotiated { anyhow::bail!("legacy relay renewal requires reconnect"); }
                    renewals.push(tokio::time::timeout(Duration::from_secs(15), service.relay_grant()));
                }
            }
            Some(result) = renewals.next(), if !renewals.is_empty() => {
                match result {
                    Ok(Ok(renewed)) => {
                        validate_runtime_grant(&renewed, &identity, runtime_id)?;
                        if renewed.account_id != grant.account_id || renewed.client_key_version != grant.client_key_version || grant_expiry(&renewed)? <= expiry {
                            return Err(RelayRejected.into());
                        }
                        renewal_id += 1;
                        let mut bytes = vec![0, 0];
                        bytes.extend(serde_json::to_vec(&serde_json::json!({ "type": "auth.renew", "id": renewal_id, "grant": renewed.grant }))?);
                        control.try_send(Message::Binary(bytes.into()))?;
                        pending_renewal = Some((renewal_id, renewed));
                    }
                    Ok(Err(error)) if !failure::retry_policy(&error).1 => return Err(error),
                    _ => { renew_at = chrono::Utc::now().timestamp() + 2; }
                }
            }
            _ = presence.tick(), if refreshes.is_empty() => { refreshes.push(service.relay_identity()); }
            Some(result) = refreshes.next(), if !refreshes.is_empty() => {
                if result.is_ok_and(|key| key.public_bytes() != identity.public_bytes()) { anyhow::bail!("relay identity changed"); }
            }
            message = read.next() => {
                last_received = tokio::time::Instant::now();
                if last_activity_report.elapsed() >= Duration::from_secs(5) {
                    let _ = inbox.send(ServerCommand::RelayActivity { generation, at: chrono::Utc::now() });
                    last_activity_report = last_received;
                }
                let bytes = match message {
                    Some(Ok(Message::Binary(bytes))) => bytes.to_vec(),
                    Some(Ok(Message::Text(text))) => text.as_bytes().to_vec(),
                    Some(Ok(Message::Ping(payload))) => { control.try_send(Message::Pong(payload))?; continue; }
                    Some(Ok(Message::Close(Some(frame)))) if u16::from(frame.code) == 4001 => return Err(failure::RelayReplaced.into()),
                    Some(Ok(Message::Close(Some(frame)))) if matches!(u16::from(frame.code), 1007..=1009) => return Err(RelayRejected.into()),
                    Some(Ok(Message::Close(_))) | None => anyhow::bail!("relay websocket closed"),
                    Some(Ok(_)) => continue,
                    Some(Err(error)) => return Err(error.into()),
                };
                if bytes.starts_with(&[0, 0]) {
                    if !negotiated || bytes.len() > 16384 { anyhow::bail!("invalid relay control"); }
                    let value: serde_json::Value = serde_json::from_slice(&bytes[2..])?;
                    if let Some((id, renewed)) = pending_renewal.take() {
                        if value["id"].as_u64() != Some(id) { pending_renewal = Some((id, renewed)); continue; }
                        if value["type"] == "auth.error" && value["code"] == "relay_authorization_unavailable" { renew_at = chrono::Utc::now().timestamp() + 2; continue; }
                        if value["type"] != "auth.renewed" || value["expiresAt"].as_i64() != Some(grant_expiry(&renewed)?) { return Err(RelayRejected.into()); }
                        expiry = grant_expiry(&renewed)?;
                        renew_at = expiry - 30;
                        grant = renewed;
                    }
                    continue;
                }
                let Ok((client_id, payload)) = relay_wire::unwrap(&bytes) else { continue; };
                if payload.is_empty() { peers.remove(&client_id); continue; }
                if payload.len() > 1024 * 1024 { peers.remove(&client_id); continue; }
                if !peers.contains_key(&client_id) {
                    if peers.len() >= MAX_MOBILE_CLIENTS || payload.len() > 16 * 1024 { continue; }
                    let peer = peer::PeerContext {
                        control_protocol: negotiated,
                        client_id: client_id.clone(), numeric_id: next_id.fetch_add(1, Ordering::Relaxed),
                        identity: identity.clone(), runtime_id: runtime_id.into(), account_id: grant.account_id.clone(),
                        verifier: verifier.clone(), output: output.clone(), inbox: inbox.clone(),
                        budget: client_budget::ClientBudget::new(budget.clone()),
                    }.spawn();
                    peers.insert(client_id.clone(), peer);
                }
                let peer = peers.get(&client_id).unwrap();
                let Some(reservation) = peer.budget.reserve_bytes(payload.len() * 2 + 256) else { peer.lifetime.alive.store(false, Ordering::Release); continue; };
                if peer.sender.try_send(peer::Packet { payload: payload.to_vec(), _reservation: reservation }).is_err() { peer.lifetime.alive.store(false, Ordering::Release); }
            }
        }
    }
}

fn validate_runtime_grant(
    grant: &RelayGrant,
    identity: &IdentityKeyPair,
    runtime_id: &str,
) -> anyhow::Result<()> {
    if grant.client_kind != "runtime"
        || grant.client_id != runtime_id
        || grant.runtime_id != runtime_id
        || grant.expires_in <= 0
        || grant.expires_in > 120
        || grant.client_key_version <= 0
        || grant.runtime_public_key.is_some()
        || grant.client_public_key != encode(identity.public_bytes())
    {
        return Err(RelayRejected.into());
    }
    Ok(())
}

fn grant_expiry(grant: &RelayGrant) -> anyhow::Result<i64> {
    use base64::Engine;
    let payload = grant
        .grant
        .split('.')
        .nth(1)
        .ok_or_else(|| anyhow::anyhow!("invalid relay grant"))?;
    let claims: serde_json::Value =
        serde_json::from_slice(&base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(payload)?)?;
    claims["exp"]
        .as_i64()
        .ok_or_else(|| anyhow::anyhow!("missing relay expiry"))
}

#[cfg(test)]
#[path = "relay_cross_language_tests.rs"]
mod cross_language_tests;
#[cfg(test)]
#[path = "relay_runtime_tests.rs"]
mod tests;

fn report(
    inbox: &UnboundedSender<ServerCommand>,
    generation: u64,
    state: &str,
    error: Option<&str>,
    retry: Option<Duration>,
) {
    let _ = inbox.send(ServerCommand::RelayStatus { generation, payload: serde_json::json!({
        "state": state, "transport": "relay", "lastError": error,
        "nextRetryAt": retry.map(|delay| chrono::Utc::now() + chrono::Duration::milliseconds(delay.as_millis() as i64)),
        "updatedAt": chrono::Utc::now(),
        "connectedAt": (state == "connected").then(chrono::Utc::now),
    }) });
}

fn grant_connection_id(token: &str) -> Option<String> {
    use base64::Engine;
    let payload = token.split('.').nth(1)?;
    let claims: serde_json::Value = serde_json::from_slice(
        &base64::engine::general_purpose::URL_SAFE_NO_PAD
            .decode(payload)
            .ok()?,
    )
    .ok()?;
    claims["jti"]
        .as_str()
        .filter(|id| !id.is_empty() && id.len() <= 128)
        .map(str::to_owned)
}
