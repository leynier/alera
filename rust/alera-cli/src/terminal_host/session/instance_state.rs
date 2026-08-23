use std::sync::atomic::{AtomicU64, Ordering};

static NEXT_SESSION_INSTANCE_ID: AtomicU64 = AtomicU64::new(1);

pub(super) fn next_session_instance_id() -> u64 {
    NEXT_SESSION_INSTANCE_ID.fetch_add(1, Ordering::Relaxed)
}
