//! Opaque replay cursors. A cursor is a retention anchor: the receive time of the oldest
//! event that may still be undelivered, so resuming from it never skips a pending event.

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

const MAX_CURSOR_BYTES: usize = 256;

#[derive(Serialize, Deserialize)]
struct Anchor {
    v: u8,
    since: i64,
}

pub fn encode(since: DateTime<Utc>) -> String {
    let anchor = Anchor {
        v: 1,
        since: since.timestamp_millis(),
    };
    URL_SAFE_NO_PAD.encode(serde_json::to_vec(&anchor).unwrap_or_default())
}

/// Decodes a cursor this server issued. Anchors in the future are refused.
pub fn decode(cursor: &str, now: DateTime<Utc>) -> Option<DateTime<Utc>> {
    if cursor.is_empty() || cursor.len() > MAX_CURSOR_BYTES {
        return None;
    }
    let bytes = URL_SAFE_NO_PAD.decode(cursor).ok()?;
    let anchor: Anchor = serde_json::from_slice(&bytes).ok()?;
    let since = DateTime::from_timestamp_millis(anchor.since)?;
    (anchor.v == 1 && since <= now + chrono::TimeDelta::minutes(1)).then_some(since)
}

#[cfg(test)]
mod tests {
    use chrono::{TimeDelta, Utc};

    use super::{decode, encode};

    #[test]
    fn round_trips_and_refuses_foreign_cursors() {
        let now = Utc::now();
        let since = now - TimeDelta::hours(3);
        let cursor = encode(since);
        assert_eq!(
            decode(&cursor, now).map(|value| value.timestamp_millis()),
            Some(since.timestamp_millis())
        );
        assert!(decode("not-a-cursor", now).is_none());
        assert!(decode(&encode(now + TimeDelta::hours(1)), now).is_none());
        assert!(decode(&"a".repeat(300), now).is_none());
    }
}
