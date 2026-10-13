use alera_provider_protocol::ProviderEvent;
use std::sync::atomic::{AtomicU64, Ordering};

static LAST_TIMESTAMP: AtomicU64 = AtomicU64::new(0);

pub(crate) fn native_message_id(started: &ProviderEvent) -> String {
    message_id_at(
        &started.event_id,
        chrono::Utc::now().timestamp_millis().cast_unsigned(),
        &LAST_TIMESTAMP,
    )
}

fn message_id_at(event_id: &str, millis: u64, last: &AtomicU64) -> String {
    let timestamp = next_timestamp(millis, last);
    // V1 uses chronological IDs as a history tie-breaker. Keep its six-byte
    // timestamp prefix and retain the event UUID's entropy across restarts.
    format!("msg_{timestamp:012x}{}", event_id.replace('-', ""))
}

fn next_timestamp(millis: u64, last: &AtomicU64) -> u64 {
    let clock = millis.saturating_mul(0x1000).saturating_add(1);
    let previous = last
        .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |previous| {
            Some(clock.max(previous.saturating_add(1)))
        })
        .expect("timestamp update always supplies a value");
    clock.max(previous.saturating_add(1)) & 0xffff_ffff_ffff
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn native_timestamps_follow_upstream_encoding_and_order_equal_or_backward_clocks() {
        let last = AtomicU64::new(0);
        let millis = 1_700_000_000_000;
        let first = next_timestamp(millis, &last);
        assert_eq!(first, (millis * 0x1000 + 1) & 0xffff_ffff_ffff);
        let same_clock = next_timestamp(millis, &last);
        assert_eq!(same_clock, first + 1);
        let backward_clock = next_timestamp(millis - 1, &last);
        assert_eq!(backward_clock, same_clock + 1);
        let next_millisecond = next_timestamp(millis + 1, &last);
        assert_eq!(
            next_millisecond,
            ((millis + 1) * 0x1000 + 1) & 0xffff_ffff_ffff
        );
        assert!(next_millisecond > backward_clock);
    }

    #[test]
    fn native_ids_sort_between_upstream_history_and_next_assistant_ids() {
        let last = AtomicU64::new(0);
        let millis = 1_700_000_000_000;
        let first = message_id_at("00000000-0000-4000-8000-000000000001", millis, &last);
        let second = message_id_at("00000000-0000-4000-8000-000000000002", millis, &last);
        // Native examples use the same timestamp encoding and a 14-character Base62 tail.
        let resumed_history = "msg_bcfe567ff00f0123456789ABCD";
        let same_millisecond_assistant = "msg_bcfe568000ff0123456789ABCD";
        let next_millisecond_assistant = "msg_bcfe568010010123456789ABCD";
        assert!(first.starts_with("msg_bcfe56800001"));
        assert!(second.starts_with("msg_bcfe56800002"));
        assert!(resumed_history < first.as_str());
        assert!(first < second);
        assert!(second.as_str() < same_millisecond_assistant);
        assert!(second.as_str() < next_millisecond_assistant);

        let restarted = AtomicU64::new(0);
        let restarted_id =
            message_id_at("00000000-0000-4000-8000-000000000003", millis, &restarted);
        assert_eq!(&first[..16], &restarted_id[..16]);
        assert_ne!(first, restarted_id);
    }
}
