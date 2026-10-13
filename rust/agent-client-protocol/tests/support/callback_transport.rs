use alera_agent_transport::{JsonTransport, TransportError};
use async_trait::async_trait;
use serde_json::Value;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use tokio::sync::{mpsc, Notify};

#[derive(Default)]
pub struct WriteGate {
    pub blocked: AtomicBool,
    pub started: Notify,
    pub released: Notify,
}

pub struct CallbackTransport {
    incoming: mpsc::Receiver<Value>,
    pub writes: Arc<Mutex<Vec<Value>>>,
    pub written: Arc<Notify>,
    pub gate: Arc<WriteGate>,
    pub closed: Arc<AtomicBool>,
    pub max_frame_bytes: usize,
}

impl CallbackTransport {
    pub fn new() -> (Self, mpsc::Sender<Value>) {
        let (sender, incoming) = mpsc::channel(8);
        (
            Self {
                incoming,
                writes: Arc::default(),
                written: Arc::default(),
                gate: Arc::default(),
                closed: Arc::default(),
                max_frame_bytes: usize::MAX,
            },
            sender,
        )
    }
}

#[async_trait]
impl JsonTransport for CallbackTransport {
    async fn send(&mut self, message: Value) -> Result<(), TransportError> {
        let observed = serde_json::to_vec(&message).unwrap().len();
        if observed > self.max_frame_bytes {
            self.closed.store(true, Ordering::SeqCst);
            return Err(TransportError::FrameTooLarge {
                limit: self.max_frame_bytes,
                observed,
            });
        }
        if message.get("method").is_none() && self.gate.blocked.load(Ordering::SeqCst) {
            self.gate.started.notify_one();
            self.gate.released.notified().await;
        }
        self.writes.lock().unwrap().push(message);
        self.written.notify_one();
        Ok(())
    }

    async fn recv(&mut self) -> Result<Option<Value>, TransportError> {
        let message = self.incoming.recv().await;
        if let Some(frame) = &message {
            let observed = serde_json::to_vec(frame).unwrap().len();
            if observed > self.max_frame_bytes {
                self.closed.store(true, Ordering::SeqCst);
                return Err(TransportError::FrameTooLarge {
                    limit: self.max_frame_bytes,
                    observed,
                });
            }
        }
        Ok(message)
    }

    async fn close(&mut self) -> Result<(), TransportError> {
        self.closed.store(true, Ordering::SeqCst);
        self.incoming.close();
        Ok(())
    }
}
