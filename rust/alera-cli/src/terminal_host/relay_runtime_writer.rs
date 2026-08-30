use super::*;
use tokio::sync::mpsc::{Receiver, UnboundedReceiver};

pub(super) struct PeerWriter {
    pub client_id: String,
    pub session: super::relay_crypto::RelaySession,
    pub inbox: UnboundedSender<ServerCommand>,
    pub output: Sender<socket_writer::Envelope>,
    pub lifetime: Arc<socket_writer::PeerLifetime>,
}

impl PeerWriter {
    pub async fn run(
        mut self,
        mut control: UnboundedReceiver<ClientFrame>,
        mut terminal: Receiver<ClientFrame>,
    ) {
        let mut binary = false;
        let mut ordering = ClientFrameOrdering::default();
        loop {
            // before_control can stage a later terminal frame. Drain it before
            // accepting another terminal item, preserving the causal watermark.
            if ordering.has_pending_terminal() {
                let frame = ordering.take_pending_terminal().unwrap();
                if self.send(frame, &mut binary).await.is_err() {
                    break;
                }
                continue;
            }
            tokio::select! {
                frame = control.recv() => {
                    let Some(frame) = frame else { break; };
                    let (preceding, frame) = ordering.before_control(frame, &mut terminal);
                    let mut failed = false;
                    for item in preceding {
                        if self.send(item, &mut binary).await.is_err() { failed = true; break; }
                    }
                    if failed || self.send(frame, &mut binary).await.is_err() { break; }
                }
                frame = terminal.recv() => {
                    let Some(frame) = frame else { break; };
                    ordering.stage_terminal(frame);
                    if self.send(ordering.take_pending_terminal().unwrap(), &mut binary).await.is_err() { break; }
                }
            }
        }
    }

    async fn send(&mut self, frame: ClientFrame, binary: &mut bool) -> anyhow::Result<()> {
        let (frame, _reservation) = match frame {
            ClientFrame::Budgeted { reservation, frame } => (*frame, Some(reservation)),
            frame => (frame, None),
        };
        if !self.lifetime.valid() {
            anyhow::bail!("relay peer expired");
        }
        match frame {
            ClientFrame::UpgradeToBinary => {
                *binary = true;
                return Ok(());
            }
            ClientFrame::RestartRuntimeAfterWrite { .. } => {
                // Every earlier enqueue awaited its actual socket write receipt.
                let _ = self.inbox.send(ServerCommand::RequestedRestart);
                return Ok(());
            }
            ClientFrame::ShutdownRuntimeAfterWrite { .. } => {
                let _ = self.inbox.send(ServerCommand::RequestedShutdown);
                return Ok(());
            }
            _ => {}
        }
        let payload = match (&frame, *binary) {
            (ClientFrame::Output { session_id, data }, true) => {
                encode_output_payload(session_id, data)
            }
            _ => serde_json::to_vec(
                &frame
                    .as_json()
                    .ok_or_else(|| anyhow::anyhow!("invalid relay frame"))?,
            )?,
        };
        let encrypted = self
            .session
            .seal(&payload)
            .map_err(|_| anyhow::anyhow!("relay encryption failed"))?;
        socket_writer::enqueue(&self.output, &self.client_id, &encrypted, &self.lifetime).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicBool, AtomicI64, AtomicU16};

    #[tokio::test]
    async fn restart_waits_for_the_response_write_receipt_and_cancellation_never_restarts() {
        for complete in [true, false] {
            let (inbox, mut commands) = mpsc::unbounded_channel();
            let (output, mut envelopes) = mpsc::channel(2);
            let local = IdentityKeyPair::generate();
            let ephemeral = IdentityKeyPair::generate();
            let remote = IdentityKeyPair::generate();
            let high = u128::from(rand_core::RngCore::next_u64(&mut rand_core::OsRng));
            let low = u128::from(rand_core::RngCore::next_u64(&mut rand_core::OsRng));
            let nonce = ((high << 64) | low).to_be_bytes();
            let (_, session) = relay_wire::derive_sessions(
                &local,
                &ephemeral,
                remote.public_bytes(),
                remote.public_bytes(),
                "runtime",
                "mobile",
                &nonce,
            )
            .unwrap();
            let lifetime = Arc::new(socket_writer::PeerLifetime {
                alive: AtomicBool::new(true),
                expires_at: AtomicI64::new(chrono::Utc::now().timestamp() + 120),
                close_code: AtomicU16::new(1013),
                connection_id: std::sync::Mutex::new(None),
                announce_connection: AtomicBool::new(false),
            });
            let (control, control_rx) = mpsc::unbounded_channel();
            let (_terminal, terminal_rx) = mpsc::channel(2);
            control
                .send(ClientFrame::Json(serde_json::json!({"id": 1, "ok": true})))
                .unwrap();
            control
                .send(ClientFrame::RestartRuntimeAfterWrite {
                    inbox: inbox.clone(),
                })
                .unwrap();
            let task = tokio::spawn(
                PeerWriter {
                    client_id: "mobile".into(),
                    session,
                    inbox,
                    output,
                    lifetime,
                }
                .run(control_rx, terminal_rx),
            );
            let response = envelopes.recv().await.unwrap();
            assert!(commands.try_recv().is_err());
            if complete {
                response.written.send(()).unwrap();
                assert!(matches!(
                    commands.recv().await,
                    Some(ServerCommand::RequestedRestart)
                ));
                task.abort();
            } else {
                drop(response);
                task.await.unwrap();
                assert!(commands.try_recv().is_err());
            }
        }
    }
}
