use super::{relay_wire, RelayWrite};
use futures_util::SinkExt;
use std::{
    collections::VecDeque,
    sync::{
        atomic::{AtomicBool, AtomicI64, Ordering},
        Arc,
    },
    time::Duration,
};
use tokio::sync::{mpsc, oneshot};
use tokio_tungstenite::tungstenite::Message;

pub(super) struct PeerLifetime {
    pub alive: AtomicBool,
    pub expires_at: AtomicI64,
    pub announce_connection: AtomicBool,
    pub connection_id: std::sync::Mutex<Option<String>>,
    pub close_code: std::sync::atomic::AtomicU16,
}

impl PeerLifetime {
    pub fn valid(&self) -> bool {
        self.alive.load(Ordering::Acquire)
            && self.expires_at.load(Ordering::Acquire) > chrono::Utc::now().timestamp()
    }
}

pub(super) struct Envelope {
    pub client_id: String,
    pub fragments: VecDeque<Vec<u8>>,
    pub lifetime: Arc<PeerLifetime>,
    pub written: oneshot::Sender<()>,
    pub announce_connection: Option<String>,
}

pub(super) async fn enqueue(
    sender: &mpsc::Sender<Envelope>,
    client_id: &str,
    payload: &[u8],
    lifetime: &Arc<PeerLifetime>,
) -> anyhow::Result<()> {
    let (written, completed) = oneshot::channel();
    sender
        .send(Envelope {
            client_id: client_id.into(),
            fragments: relay_wire::fragment(payload)?.into(),
            lifetime: lifetime.clone(),
            written,
            announce_connection: if lifetime.announce_connection.swap(false, Ordering::AcqRel) {
                lifetime.connection_id.lock().unwrap().clone()
            } else {
                None
            },
        })
        .await
        .map_err(|_| anyhow::anyhow!("relay socket writer stopped"))?;
    completed
        .await
        .map_err(|_| anyhow::anyhow!("relay frame was not written"))
}

pub(super) async fn run(
    mut write: RelayWrite,
    mut frames: mpsc::Receiver<Envelope>,
    mut control: mpsc::Receiver<Message>,
) -> anyhow::Result<()> {
    let mut ready = VecDeque::<Envelope>::new();
    loop {
        if ready.is_empty() {
            tokio::select! {
                frame = frames.recv() => match frame { Some(frame) => ready.push_back(frame), None => return Ok(()) },
                message = control.recv() => match message { Some(message) => send(&mut write, message).await?, None => return Ok(()) },
            }
        }
        // Each peer has at most one envelope outstanding. Alternate fragments,
        // without allowing a large snapshot to monopolize the shared socket.
        for _ in 0..16 {
            match frames.try_recv() {
                Ok(frame) => ready.push_back(frame),
                Err(_) => break,
            }
        }
        if let Ok(message) = control.try_recv() {
            send(&mut write, message).await?;
        }
        if let Some(mut frame) = ready.pop_front() {
            if !frame.lifetime.valid() {
                continue;
            }
            if let Some(connection_id) = frame.announce_connection.take() {
                let mut bytes = vec![0, 0];
                bytes.extend(serde_json::to_vec(&serde_json::json!({ "type": "peer.ready", "clientId": frame.client_id, "connectionId": connection_id }))?);
                send(&mut write, Message::Binary(bytes.into())).await?;
            }
            if let Some(fragment) = frame.fragments.pop_front() {
                send(
                    &mut write,
                    Message::Binary(relay_wire::wrap(&frame.client_id, &fragment)?.into()),
                )
                .await?;
            }
            if frame.fragments.is_empty() {
                let _ = frame.written.send(());
            } else {
                ready.push_back(frame);
            }
        }
    }
}

async fn send(write: &mut RelayWrite, message: Message) -> anyhow::Result<()> {
    tokio::time::timeout(Duration::from_secs(5), write.send(message)).await??;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures_util::StreamExt;
    use tokio::net::TcpListener;

    #[tokio::test]
    async fn interleaves_peers_and_confirms_only_fully_written_envelopes() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let accepted = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            tokio_tungstenite::accept_async(stream).await.unwrap()
        });
        let (socket, _) = tokio_tungstenite::connect_async(format!("ws://{address}"))
            .await
            .unwrap();
        let mut reader = accepted.await.unwrap();
        let (write, _) = socket.split();
        let (frames, receiver) = mpsc::channel(16);
        let (_control, control_rx) = mpsc::channel(16);
        let lifetime = Arc::new(PeerLifetime {
            alive: AtomicBool::new(true),
            expires_at: AtomicI64::new(chrono::Utc::now().timestamp() + 120),
            close_code: std::sync::atomic::AtomicU16::new(1013),
            connection_id: std::sync::Mutex::new(None),
            announce_connection: AtomicBool::new(false),
        });
        let (written_one, mut receipt_one) = oneshot::channel();
        let (written_two, receipt_two) = oneshot::channel();
        frames
            .send(Envelope {
                client_id: "one".into(),
                fragments: vec![vec![1], vec![2], vec![3]].into(),
                lifetime: lifetime.clone(),
                written: written_one,
                announce_connection: None,
            })
            .await
            .unwrap();
        frames
            .send(Envelope {
                client_id: "two".into(),
                fragments: vec![vec![4]].into(),
                lifetime,
                written: written_two,
                announce_connection: None,
            })
            .await
            .unwrap();
        assert!(receipt_one.try_recv().is_err());
        let writer = tokio::spawn(run(write, receiver, control_rx));
        let mut ids = Vec::new();
        for _ in 0..4 {
            let Message::Binary(frame) = reader.next().await.unwrap().unwrap() else {
                panic!("binary frame expected")
            };
            ids.push(relay_wire::unwrap(&frame).unwrap().0);
        }
        assert_eq!(ids, ["one", "two", "one", "one"]);
        receipt_one.await.unwrap();
        receipt_two.await.unwrap();
        writer.abort();
    }
}
