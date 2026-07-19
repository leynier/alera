use serde_json::{json, Value};

/// Who currently owns the PTY viewport of a session. A mobile client claims
/// the driver seat by attaching or resizing; the desktop takes it back with
/// `terminal.reclaim`. Mirrors Orca's mobile presence lock.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SessionDriver {
    Idle,
    Desktop,
    Mobile {
        client_id: u64,
        device_id: String,
        device_name: String,
    },
}

impl SessionDriver {
    pub fn payload(&self) -> Value {
        match self {
            SessionDriver::Idle => json!({ "kind": "idle" }),
            SessionDriver::Desktop => json!({ "kind": "desktop" }),
            SessionDriver::Mobile {
                device_id,
                device_name,
                ..
            } => json!({
                "kind": "mobile",
                "deviceId": device_id,
                "deviceName": device_name,
            }),
        }
    }
}
