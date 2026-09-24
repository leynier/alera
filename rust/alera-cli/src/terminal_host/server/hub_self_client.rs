//! The hub's own client: how the hub answers a satellite's question.
//!
//! The reverse channel does not interpret a forwarded verb. The hub sends it to
//! itself as an ordinary local authenticated client, so every handler,
//! validation, broadcast and job the desktop CLI reaches applies unchanged.
//!
//! One connection per origin host, kept between questions: a buffer guard
//! acquired by one request must be claimed by the next from the same client
//! id, so a fresh connection per request would break `workspace remove`. The
//! connection closes after an idle spell, because an authenticated client keeps
//! an otherwise empty runtime from shutting itself down.

use std::collections::HashMap;
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicI64, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde_json::{json, Value};
use tokio::io::AsyncWriteExt;
use tokio::sync::{mpsc, oneshot};

use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::host_link::response_result;

const IDLE_CLOSE: Duration = Duration::from_secs(30);
const PENDING_POISONED: &str = "hub self client pending map poisoned";

#[derive(Clone, Default)]
pub(super) struct HubSelfClientPool {
    clients: Arc<tokio::sync::Mutex<HashMap<String, Arc<HubSelfClient>>>>,
}

impl HubSelfClientPool {
    /// Sends `request_type` to the runtime at `runtime_dir` on the connection
    /// that answers `origin_host_id`, opening it first when needed.
    pub(super) async fn request(
        &self,
        runtime_dir: &Path,
        origin_host_id: &str,
        request_type: &str,
        payload: Value,
        deadline: Duration,
    ) -> HostResult<Value> {
        let client = self.client_for(runtime_dir, origin_host_id).await?;
        let result = client.request(request_type, payload, deadline).await;
        self.close_when_idle(origin_host_id, &client);
        result
    }

    async fn client_for(
        &self,
        runtime_dir: &Path,
        origin_host_id: &str,
    ) -> HostResult<Arc<HubSelfClient>> {
        let mut clients = self.clients.lock().await;
        if let Some(client) = clients.get(origin_host_id) {
            if !client.is_closed() {
                return Ok(client.clone());
            }
        }
        let client = Arc::new(HubSelfClient::connect(runtime_dir).await?);
        clients.insert(origin_host_id.to_string(), client.clone());
        Ok(client)
    }

    fn close_when_idle(&self, origin_host_id: &str, client: &Arc<HubSelfClient>) {
        let generation = client.generation.load(Ordering::SeqCst);
        let pool = self.clone();
        let client = client.clone();
        let origin_host_id = origin_host_id.to_string();
        tokio::spawn(async move {
            tokio::time::sleep(IDLE_CLOSE).await;
            if client.generation.load(Ordering::SeqCst) != generation || client.in_flight() > 0 {
                return;
            }
            client.close();
            let mut clients = pool.clients.lock().await;
            if clients
                .get(&origin_host_id)
                .is_some_and(|current| Arc::ptr_eq(current, &client))
            {
                clients.remove(&origin_host_id);
            }
        });
    }
}

pub(super) struct HubSelfClient {
    outbound: mpsc::UnboundedSender<Option<String>>,
    pending: Arc<Mutex<HashMap<i64, oneshot::Sender<Value>>>>,
    next_id: AtomicI64,
    /// Bumped by every request, so an idle check knows whether the connection
    /// was used again after it was scheduled.
    generation: AtomicU64,
    closed: Arc<AtomicBool>,
}

impl HubSelfClient {
    async fn connect(runtime_dir: &Path) -> HostResult<Self> {
        let client = RuntimeHostRpcClient::connect(runtime_dir)
            .await
            .map_err(|error| {
                HostError::state(format!(
                    "The Alera desktop runtime could not reach itself to answer a remote host: {error}"
                ))
            })?
            .ok_or_else(|| {
                HostError::state(
                    "The Alera desktop runtime could not reach itself to answer a remote host.",
                )
            })?;
        let (mut lines, mut writer, next_id) = client.into_terminal_transport();
        let (outbound, mut queue) = mpsc::unbounded_channel::<Option<String>>();
        let pending: Arc<Mutex<HashMap<i64, oneshot::Sender<Value>>>> = Default::default();
        let closed = Arc::new(AtomicBool::new(false));
        tokio::spawn(async move {
            while let Some(Some(line)) = queue.recv().await {
                if writer.write_all(line.as_bytes()).await.is_err()
                    || writer.write_all(b"\n").await.is_err()
                    || writer.flush().await.is_err()
                {
                    break;
                }
            }
            let _ = writer.shutdown().await;
        });
        {
            let pending = pending.clone();
            let closed = closed.clone();
            let outbound = outbound.clone();
            tokio::spawn(async move {
                while let Ok(Some(line)) = lines.next_line().await {
                    let Ok(frame) = serde_json::from_str::<Value>(&line) else {
                        continue;
                    };
                    if frame.get("event").is_some() {
                        continue;
                    }
                    let Some(id) = frame.get("id").and_then(Value::as_i64) else {
                        continue;
                    };
                    let sender = pending.lock().expect(PENDING_POISONED).remove(&id);
                    if let Some(sender) = sender {
                        let _ = sender.send(frame);
                    }
                }
                closed.store(true, Ordering::SeqCst);
                let _ = outbound.send(None);
                // Dropping the senders fails every waiting request at once.
                pending.lock().expect(PENDING_POISONED).clear();
            });
        }
        Ok(Self {
            outbound,
            pending,
            next_id: AtomicI64::new(next_id),
            generation: AtomicU64::new(0),
            closed,
        })
    }

    fn is_closed(&self) -> bool {
        self.closed.load(Ordering::SeqCst) || self.outbound.is_closed()
    }

    fn in_flight(&self) -> usize {
        self.pending.lock().expect(PENDING_POISONED).len()
    }

    fn close(&self) {
        self.closed.store(true, Ordering::SeqCst);
        let _ = self.outbound.send(None);
    }

    async fn request(
        &self,
        request_type: &str,
        payload: Value,
        deadline: Duration,
    ) -> HostResult<Value> {
        self.generation.fetch_add(1, Ordering::SeqCst);
        if self.is_closed() {
            return Err(closed_error());
        }
        let id = self.next_id.fetch_add(1, Ordering::SeqCst);
        let (sender, receiver) = oneshot::channel();
        self.pending
            .lock()
            .expect(PENDING_POISONED)
            .insert(id, sender);
        let line = serde_json::to_string(&json!({
            "id": id,
            "type": request_type,
            "payload": payload,
        }))
        .map_err(|error| HostError::format(error.to_string()))?;
        if self.outbound.send(Some(line)).is_err() {
            self.pending.lock().expect(PENDING_POISONED).remove(&id);
            return Err(closed_error());
        }
        match tokio::time::timeout(deadline, receiver).await {
            Ok(Ok(frame)) => response_result(&frame),
            Ok(Err(_)) => Err(closed_error()),
            Err(_) => {
                self.pending.lock().expect(PENDING_POISONED).remove(&id);
                Err(HostError::state(format!(
                    "The Alera desktop did not finish {request_type} within {}s.",
                    deadline.as_secs()
                )))
            }
        }
    }
}

fn closed_error() -> HostError {
    HostError::state(
        "The Alera desktop runtime closed the connection it was answering a remote host on. Retry.",
    )
}
