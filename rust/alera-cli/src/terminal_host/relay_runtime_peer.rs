use super::client_budget::{ClientBudget, FrameReservation};
use super::relay_runtime_auth::{decode_fixed, decode_nonce, GrantClaims, GrantVerifier};
use super::*;
use std::sync::atomic::AtomicBool;
use tokio::sync::mpsc::Receiver;

pub(super) struct Packet {
    pub payload: Vec<u8>,
    pub _reservation: Arc<FrameReservation>,
}

pub(super) struct Peer {
    pub task: JoinHandle<()>,
    pub sender: Sender<Packet>,
    pub lifetime: Arc<socket_writer::PeerLifetime>,
    pub budget: ClientBudget,
}

impl Drop for Peer {
    fn drop(&mut self) {
        self.lifetime.alive.store(false, Ordering::Release);
        self.task.abort();
    }
}

pub(super) struct PeerContext {
    pub control_protocol: bool,
    pub client_id: String,
    pub numeric_id: u64,
    pub identity: Arc<IdentityKeyPair>,
    pub runtime_id: String,
    pub account_id: String,
    pub verifier: GrantVerifier,
    pub output: Sender<socket_writer::Envelope>,
    pub inbox: UnboundedSender<ServerCommand>,
    pub budget: ClientBudget,
}

struct ConnectedGuard {
    id: u64,
    inbox: UnboundedSender<ServerCommand>,
    writer: JoinHandle<()>,
}

impl Drop for ConnectedGuard {
    fn drop(&mut self) {
        self.writer.abort();
        let _ = self
            .inbox
            .send(ServerCommand::ClientDisconnected { id: self.id });
    }
}

impl PeerContext {
    pub fn spawn(self) -> Peer {
        let (sender, incoming) = mpsc::channel(64);
        let lifetime = Arc::new(socket_writer::PeerLifetime {
            alive: AtomicBool::new(true),
            expires_at: std::sync::atomic::AtomicI64::new(chrono::Utc::now().timestamp() + 10),
            connection_id: std::sync::Mutex::new(None),
            announce_connection: AtomicBool::new(self.control_protocol),
            close_code: std::sync::atomic::AtomicU16::new(1013),
        });
        let budget = self.budget.clone();
        let task_lifetime = lifetime.clone();
        let task = tokio::spawn(async move {
            let result = self.serve(incoming, &task_lifetime).await;
            task_lifetime.alive.store(false, Ordering::Release);
            if result.is_err() {
                tracing::debug!("relay peer ended or rejected a frame");
            }
        });
        Peer {
            task,
            sender,
            lifetime,
            budget,
        }
    }

    async fn serve(
        self,
        mut incoming: Receiver<Packet>,
        lifetime: &Arc<socket_writer::PeerLifetime>,
    ) -> anyhow::Result<()> {
        let handshake = async {
            let packet = incoming
                .recv()
                .await
                .ok_or_else(|| anyhow::anyhow!("relay peer disconnected"))?;
            let hello: relay_wire::RelayHello = relay_wire::decode_json(&packet.payload)?;
            // Bind cleanup to this handshake, never to a replacement socket.
            if let Some(id) = grant_connection_id(&hello.grant) {
                *lifetime.connection_id.lock().unwrap() = Some(id);
            }
            let claims = self
                .verifier
                .verify(&hello.grant)
                .await
                .inspect_err(|error| {
                    if !error.is::<relay_runtime_auth::GrantKeysUnavailable>() {
                        lifetime.close_code.store(4004, Ordering::Release);
                    }
                })?;
            self.validate_hello(&hello, &claims).inspect_err(|_| {
                lifetime.close_code.store(4004, Ordering::Release);
            })?;
            let ephemeral = IdentityKeyPair::generate();
            let nonce = decode_nonce(&hello.nonce)?;
            let (receive, send) = relay_wire::derive_sessions(
                &self.identity,
                &ephemeral,
                decode_fixed(&hello.identity_public_key)?,
                decode_fixed(&hello.ephemeral_public_key)?,
                &self.runtime_id,
                &self.client_id,
                &nonce,
            )
            .map_err(|_| anyhow::anyhow!("relay key derivation failed"))?;
            let ack = relay_wire::RelayHelloAck {
                version: relay_wire::RELAY_HELLO_VERSION,
                runtime_id: self.runtime_id.clone(),
                client_id: self.client_id.clone(),
                identity_public_key: encode(self.identity.public_bytes()),
                ephemeral_public_key: encode(ephemeral.public_bytes()),
                nonce: encode(nonce),
                confirmation: encode(send.confirmation()),
            };
            socket_writer::enqueue(
                &self.output,
                &self.client_id,
                &relay_wire::encode_json(&ack)?,
                lifetime,
            )
            .await?;
            let confirmation = incoming
                .recv()
                .await
                .ok_or_else(|| anyhow::anyhow!("relay confirmation missing"))?;
            let confirmation: relay_wire::RelayConfirmation =
                relay_wire::decode_json(&confirmation.payload)?;
            if confirmation.version != relay_wire::RELAY_HELLO_VERSION {
                lifetime.close_code.store(4004, Ordering::Release);
                anyhow::bail!("unsupported relay confirmation");
            }
            receive
                .verify_peer_confirmation(&decode_fixed(&confirmation.confirmation)?)
                .map_err(|_| {
                    lifetime.close_code.store(4004, Ordering::Release);
                    anyhow::anyhow!("relay confirmation failed")
                })?;
            Ok::<_, anyhow::Error>((claims, receive, send))
        };
        let (mut claims, mut receive, send) =
            tokio::time::timeout(Duration::from_secs(10), handshake).await??;
        if !lifetime.valid() {
            anyhow::bail!("relay handshake expired");
        }
        lifetime.expires_at.store(claims.exp, Ordering::Release);
        let (control_tx, control_rx) = mpsc::unbounded_channel();
        let (terminal_tx, terminal_rx) = mpsc::channel(MOBILE_CLIENT_TERMINAL_OUT_QUEUE_CAPACITY);
        let handle = ClientHandle::new(control_tx, terminal_tx).with_budget(self.budget.clone());
        let writer = writer::PeerWriter {
            client_id: self.client_id.clone(),
            session: send,
            inbox: self.inbox.clone(),
            output: self.output.clone(),
            lifetime: lifetime.clone(),
        };
        let mut connected = ConnectedGuard {
            id: self.numeric_id,
            inbox: self.inbox.clone(),
            writer: tokio::spawn(writer.run(control_rx, terminal_rx)),
        };
        self.inbox.send(ServerCommand::RelayClientConnected {
            id: self.numeric_id,
            handle: handle.clone(),
            client_id: self.client_id.clone(),
        })?;
        let mut fragments = relay_wire::FragmentReassembler::default();
        let mut partial_since: Option<tokio::time::Instant> = None;
        let mut assembly_reservation = None;
        loop {
            let packet = tokio::select! {
                _ = &mut connected.writer => anyhow::bail!("relay peer writer stopped"),
                packet = incoming.recv() => packet.ok_or_else(|| anyhow::anyhow!("relay peer disconnected"))?,
                _ = tokio::time::sleep_until(partial_since.map(|at| at + Duration::from_secs(10)).unwrap_or_else(|| tokio::time::Instant::now() + Duration::from_secs(86400))), if partial_since.is_some() => anyhow::bail!("relay fragments expired"),
            };
            if !lifetime.valid() {
                anyhow::bail!("relay authorization expired");
            }
            let Some(envelope) = fragments.accept(&packet.payload)? else {
                if partial_since.is_none() {
                    assembly_reservation = Some(
                        self.budget
                            .reserve_bytes(1024 * 1024)
                            .ok_or_else(|| anyhow::anyhow!("relay assembly budget exceeded"))?,
                    );
                    partial_since = Some(tokio::time::Instant::now());
                }
                continue;
            };
            partial_since = None;
            let assembly = assembly_reservation.take();
            let clear = receive.open(&envelope).map_err(|_| {
                lifetime.close_code.store(4004, Ordering::Release);
                anyhow::anyhow!("relay decryption failed")
            })?;
            let line = String::from_utf8(clear)?;
            let request: serde_json::Value = serde_json::from_str(&line)?;
            if request["type"] == "mobile.relayAuthorization.renew" {
                let token = request["payload"]["grant"]
                    .as_str()
                    .ok_or_else(|| anyhow::anyhow!("missing renewal grant"))?;
                let renewed = self.verifier.verify(token).await.inspect_err(|error| {
                    if !error.is::<relay_runtime_auth::GrantKeysUnavailable>() {
                        lifetime.close_code.store(4004, Ordering::Release);
                    }
                })?;
                if !lifetime.valid() {
                    anyhow::bail!("relay authorization expired");
                }
                if !claims.same_identity(&renewed)
                    || (claims.jti != renewed.jti && renewed.exp <= claims.exp)
                {
                    lifetime.close_code.store(4004, Ordering::Release);
                    anyhow::bail!("relay renewal changed identity or expired");
                }
                lifetime.expires_at.store(renewed.exp, Ordering::Release);
                claims = renewed;
                handle.send_control(ClientFrame::Json(serde_json::json!({ "id": request["id"], "ok": true, "payload": { "expiresAt": claims.exp } })))?;
            } else {
                let (accepted, processed) = oneshot::channel();
                self.inbox.send(ServerCommand::RelayClientLine {
                    id: self.numeric_id,
                    line,
                    accepted,
                    expires_at: claims.exp,
                })?;
                processed.await?;
            }
            drop(assembly);
        }
    }

    fn validate_hello(
        &self,
        hello: &relay_wire::RelayHello,
        claims: &GrantClaims,
    ) -> anyhow::Result<()> {
        if hello.version != relay_wire::RELAY_HELLO_VERSION
            || claims.role != "mobile"
            || claims.runtime_id != self.runtime_id
            || claims.client_id != self.client_id
            || hello.client_id != self.client_id
            || hello.runtime_id != self.runtime_id
            || hello.account_id != claims.account_id
            || claims.account_id != self.account_id
            || hello.key_version != claims.key_version
            || hello.identity_public_key != claims.client_public_key
            || claims.runtime_public_key != encode(self.identity.public_bytes())
        {
            anyhow::bail!("relay mobile grant is out of scope");
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn cancellation_releases_the_actor_client_and_aborts_its_writer() {
        let (inbox, mut receiver) = mpsc::unbounded_channel();
        let writer = tokio::spawn(std::future::pending::<()>());
        let abort = writer.abort_handle();
        let guard = ConnectedGuard {
            id: 42,
            inbox,
            writer,
        };
        drop(guard);
        assert!(matches!(
            receiver.recv().await,
            Some(ServerCommand::ClientDisconnected { id: 42 })
        ));
        tokio::task::yield_now().await;
        assert!(abort.is_finished());
    }
}
