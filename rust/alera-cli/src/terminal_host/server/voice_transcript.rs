//! Merging and dispatching realtime transcript fragments.

pub(super) fn merge_pending_transcript(flushed: &str, pending: &str, incoming: &str) -> String {
    let incoming = normalize_transcript(incoming);
    let flushed = normalize_transcript(flushed);
    let pending = normalize_transcript(pending);
    if incoming.is_empty() {
        return pending;
    }
    if is_transcript_prefix(&incoming, &flushed) && incoming != flushed {
        return pending;
    }
    if incoming == flushed {
        return pending;
    }
    if !pending.is_empty() && is_transcript_prefix(&incoming, &pending) && incoming != pending {
        return pending;
    }
    if !flushed.is_empty() && is_transcript_prefix(&flushed, &incoming) {
        return incoming;
    }
    if pending.is_empty() {
        return if flushed.is_empty() {
            incoming
        } else {
            join_transcript(&flushed, &incoming)
        };
    }
    let pending_already_includes_flushed =
        flushed.is_empty() || is_transcript_prefix(&flushed, &pending);
    let full = if pending_already_includes_flushed {
        pending.clone()
    } else {
        join_transcript(&flushed, &pending)
    };
    if is_transcript_prefix(&full, &incoming) {
        return incoming;
    }
    if is_transcript_prefix(&incoming, &full) {
        return pending;
    }
    if is_transcript_prefix(&pending, &incoming) {
        return if pending_already_includes_flushed {
            incoming
        } else {
            join_transcript(&flushed, &incoming)
        };
    }
    if is_transcript_prefix(&incoming, &pending) {
        return pending;
    }
    if pending_already_includes_flushed {
        join_transcript(&pending, &incoming)
    } else {
        join_transcript(&full, &incoming)
    }
}

pub(super) fn transcript_dispatch(
    flushed: Option<&str>,
    pending: &str,
) -> Option<(String, String)> {
    let pending = normalize_transcript(pending);
    if pending.is_empty() {
        return None;
    }
    let flushed = flushed.map(normalize_transcript).unwrap_or_default();
    if pending == flushed {
        return None;
    }
    if !flushed.is_empty() && is_transcript_prefix(&pending, &flushed) && pending != flushed {
        return None;
    }
    if !flushed.is_empty() && is_transcript_prefix(&flushed, &pending) {
        let extra = pending[flushed.len()..].trim().to_string();
        if extra.is_empty() {
            return None;
        }
        return Some((pending, extra));
    }
    Some((join_transcript(&flushed, &pending), pending))
}

fn normalize_transcript(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn join_transcript(left: &str, right: &str) -> String {
    match (left.is_empty(), right.is_empty()) {
        (true, true) => String::new(),
        (true, false) => right.to_string(),
        (false, true) => left.to_string(),
        (false, false) => format!("{left} {right}"),
    }
}

pub(super) fn is_transcript_prefix(prefix: &str, full: &str) -> bool {
    if prefix.is_empty() || full == prefix {
        return true;
    }
    full.starts_with(prefix) && full[prefix.len()..].starts_with(' ')
}
