use super::client::ClientFrame;
use std::sync::Arc;
use tokio::sync::{OwnedSemaphorePermit, Semaphore};

pub const RELAY_PEER_BYTES: usize = 4 * 1024 * 1024;
pub const RELAY_RUNTIME_BYTES: usize = 32 * 1024 * 1024;

#[derive(Clone, Debug)]
pub struct ClientBudget {
    peer: Arc<Semaphore>,
    exhausted: Arc<std::sync::atomic::AtomicBool>,
    runtime: Arc<Semaphore>,
}

#[derive(Debug)]
pub struct FrameReservation {
    _peer: OwnedSemaphorePermit,
    _runtime: OwnedSemaphorePermit,
}

impl ClientBudget {
    pub fn new(runtime: Arc<Semaphore>) -> Self {
        Self {
            peer: Arc::new(Semaphore::new(RELAY_PEER_BYTES)),
            runtime,
            exhausted: Arc::new(std::sync::atomic::AtomicBool::new(false)),
        }
    }

    pub fn disconnect(&self) {
        self.exhausted
            .store(true, std::sync::atomic::Ordering::Release);
    }
    pub fn is_exhausted(&self) -> bool {
        self.exhausted.load(std::sync::atomic::Ordering::Acquire)
    }

    pub fn reserve(&self, frame: ClientFrame) -> Result<ClientFrame, ClientFrame> {
        let bytes = frame_bytes(&frame).saturating_mul(2).saturating_add(256);
        let Some(reservation) = self.reserve_bytes(bytes) else {
            return Err(frame);
        };
        Ok(ClientFrame::Budgeted {
            reservation,
            frame: Box::new(frame),
        })
    }

    pub fn reserve_bytes(&self, bytes: usize) -> Option<Arc<FrameReservation>> {
        let bytes = u32::try_from(bytes).ok()?;
        let peer = self.peer.clone().try_acquire_many_owned(bytes).ok()?;
        let runtime = self.runtime.clone().try_acquire_many_owned(bytes).ok()?;
        Some(Arc::new(FrameReservation {
            _peer: peer,
            _runtime: runtime,
        }))
    }
}

fn frame_bytes(frame: &ClientFrame) -> usize {
    match frame {
        ClientFrame::Output { session_id, data } => session_id.len() + data.len(),
        ClientFrame::Json(value) => json_bytes(value),
        ClientFrame::OrderedControl { frame, .. }
        | ClientFrame::SequencedTerminal { frame, .. }
        | ClientFrame::Budgeted { frame, .. } => frame_bytes(frame),
        _ => 0,
    }
}

fn json_bytes(value: &serde_json::Value) -> usize {
    // Conservative retained-memory estimate, including JSON escaping and map overhead.
    match value {
        serde_json::Value::String(value) => string_bytes(value) + 32,
        serde_json::Value::Array(values) => {
            values.iter().map(json_bytes).sum::<usize>() + values.len() * 32
        }
        serde_json::Value::Object(values) => values
            .iter()
            .map(|(key, value)| string_bytes(key) + 96 + json_bytes(value))
            .sum(),
        _ => 32,
    }
}

fn string_bytes(value: &str) -> usize {
    value
        .bytes()
        .map(|byte| match byte {
            b'"' | b'\\' | b'\n' | b'\r' | b'\t' | 8 | 12 => 2,
            0..=31 => 6,
            _ => 1,
        })
        .sum()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn reservation_survives_clones_and_releases_when_the_last_owner_drops() {
        let runtime = Arc::new(Semaphore::new(RELAY_RUNTIME_BYTES));
        let budget = ClientBudget::new(runtime.clone());
        let frame = || ClientFrame::Output {
            session_id: "s".into(),
            data: vec![0; 1024 * 1024],
        };
        let first = budget.reserve(frame()).unwrap();
        let clone = first.clone();
        assert!(budget.reserve(frame()).is_err());
        drop(first);
        assert!(budget.reserve(frame()).is_err());
        drop(clone);
        assert_eq!(runtime.available_permits(), RELAY_RUNTIME_BYTES);
        assert!(budget.reserve(frame()).is_ok());
    }
    #[test]
    fn relay_peers_cannot_exceed_the_shared_runtime_budget() {
        let runtime = Arc::new(Semaphore::new(RELAY_RUNTIME_BYTES));
        let peers = (0..9)
            .map(|_| ClientBudget::new(runtime.clone()))
            .collect::<Vec<_>>();
        let mut reservations = Vec::new();
        for peer in peers.iter().take(8) {
            reservations.push(peer.reserve_bytes(RELAY_PEER_BYTES).unwrap());
        }
        assert!(peers[8].reserve_bytes(1).is_none());
        assert_eq!(runtime.available_permits(), 0);
        reservations.pop();
        assert!(peers[8].reserve_bytes(RELAY_PEER_BYTES).is_some());
    }
}
