use alera_core::runtime::{is_external_inbox, OrchestrationMessage, OrchestrationMessagePriority};

const BANNER_WIDTH: usize = 60;
const INJECT_BODY_MAX_BYTES: usize = 4 * 1024;
const INJECT_PAYLOAD_MAX_BYTES: usize = 2 * 1024;
const INJECT_BATCH_MAX_BYTES: usize = 16 * 1024;
const INJECT_BATCH_RESERVED_BYTES: usize = 512;

/// Rich message banners help agents (and humans reading terminal output)
/// quickly parse message metadata. Priority indicators surface urgent
/// messages visually; the reply hint reduces friction for agent-to-agent
/// responses.
pub fn format_message_banner(message: &OrchestrationMessage) -> String {
    let priority_tag = match message.priority {
        OrchestrationMessagePriority::Urgent => " [URGENT]",
        OrchestrationMessagePriority::High => " [HIGH]",
        OrchestrationMessagePriority::Normal => "",
    };
    let external = is_external_inbox(&message.from_handle);
    let mut lines = vec![if external {
        format!(
            "──── External question from {from}{via}{priority_tag} ({message_type}) ────",
            from = message.from_handle,
            via = external_origin_suffix(message),
            message_type = message.message_type.as_str(),
        )
    } else {
        format!(
            "──── From: {sender_name} ({from}){priority_tag} ({message_type}) ────",
            sender_name = message.from_handle.to_uppercase(),
            from = message.from_handle,
            message_type = message.message_type.as_str(),
        )
    }];
    lines.push(format!("Subject: {}", message.subject));
    if !message.body.is_empty() {
        let (body, truncated) = truncate_utf8(&message.body, INJECT_BODY_MAX_BYTES);
        lines.push(body.to_string());
        if truncated {
            lines.push(format!(
                "[Message body truncated; run alera orchestration inbox --terminal {} for full content]",
                message.to_handle
            ));
        }
    }
    if let Some(payload) = &message.payload {
        let (payload, truncated) = truncate_utf8(payload, INJECT_PAYLOAD_MAX_BYTES);
        lines.push(format!(
            "[Payload: {payload}{}]",
            if truncated { "…" } else { "" }
        ));
    }
    if external {
        // The asker reads only the reply; text left in the terminal is lost.
        lines.push(
            "[The sender cannot read this terminal. Put your complete answer in the reply.]"
                .to_string(),
        );
        lines.push(format!(
            "[Reply: alera orchestration reply --id {} --body \"...\", or --body-file <path> for a long answer]",
            message.id
        ));
    } else {
        lines.push(format!(
            "[Reply: alera orchestration reply --id {} --body \"...\"]",
            message.id
        ));
    }
    lines.push("─".repeat(BANNER_WIDTH));
    lines.join("\n")
}

/// Longest MCP client name shown in a banner; the name is self-asserted.
const ORIGIN_CLIENT_NAME_MAX_CHARS: usize = 64;

fn external_origin_suffix(message: &OrchestrationMessage) -> String {
    let origin = message
        .external_meta
        .as_ref()
        .and_then(|meta| meta.get("origin"));
    let field = |name: &str| origin.and_then(|origin| origin.get(name)?.as_str());
    match field("surface") {
        Some("desktop") => " via Alera desktop".to_string(),
        Some("mobile") => " via Alera mobile".to_string(),
        Some("mcp") => {
            let name: String = field("clientName")
                .or_else(|| field("clientId"))
                .unwrap_or("an MCP client")
                .chars()
                .filter(|character| !character.is_control())
                .take(ORIGIN_CLIENT_NAME_MAX_CHARS)
                .collect();
            format!(" via {} (MCP)", name.trim())
        }
        _ => String::new(),
    }
}

/// How many leading messages fit in one injected batch. Delivery pastes only
/// these and leaves the rest queued for the agent's next turn.
pub fn injected_message_count(messages: &[OrchestrationMessage]) -> usize {
    let content_limit = INJECT_BATCH_MAX_BYTES.saturating_sub(INJECT_BATCH_RESERVED_BYTES);
    let mut used_bytes = 0usize;
    let mut count = 0;
    for message in messages {
        let separator_bytes = if count == 0 { 0 } else { 2 };
        let next = used_bytes
            .saturating_add(separator_bytes)
            .saturating_add(format_message_banner(message).len());
        if count > 0 && next > content_limit {
            break;
        }
        used_bytes = next;
        count += 1;
    }
    count
}

/// Grouping banners under a single wrapper line lets agents detect the
/// message block boundary and parse each banner individually.
pub fn format_messages_for_injection(messages: &[OrchestrationMessage]) -> String {
    if messages.is_empty() {
        return String::new();
    }
    let mut banners = Vec::new();
    let mut used_bytes = 0usize;
    let content_limit = INJECT_BATCH_MAX_BYTES.saturating_sub(INJECT_BATCH_RESERVED_BYTES);
    for message in messages {
        let banner = format_message_banner(message);
        let separator_bytes = if banners.is_empty() { 0 } else { 2 };
        if used_bytes
            .saturating_add(separator_bytes)
            .saturating_add(banner.len())
            > content_limit
        {
            let notice = format!(
                "[{} additional message(s) omitted; run alera orchestration inbox --terminal {}]",
                messages.len().saturating_sub(banners.len()),
                message.to_handle
            );
            if used_bytes
                .saturating_add(separator_bytes)
                .saturating_add(notice.len())
                <= content_limit
            {
                banners.push(notice);
            }
            break;
        }
        used_bytes = used_bytes.saturating_add(separator_bytes + banner.len());
        banners.push(banner);
    }
    let banners = banners.join("\n\n");
    format!(
        "\n--- Orchestration Messages ({}) ---\n{banners}\n---\n",
        messages.len()
    )
}

fn truncate_utf8(value: &str, max_bytes: usize) -> (&str, bool) {
    if value.len() <= max_bytes {
        return (value, false);
    }
    let mut end = max_bytes;
    while !value.is_char_boundary(end) {
        end = end.saturating_sub(1);
    }
    (&value[..end], true)
}

#[cfg(test)]
mod tests {
    use super::*;
    use alera_core::runtime::OrchestrationMessageType;

    fn message(priority: OrchestrationMessagePriority) -> OrchestrationMessage {
        OrchestrationMessage {
            id: "msg_1".to_string(),
            from_handle: "term_a".to_string(),
            to_handle: "term_b".to_string(),
            subject: "Build done".to_string(),
            body: "All green.".to_string(),
            message_type: OrchestrationMessageType::Status,
            priority,
            thread_id: None,
            payload: Some("{\"x\":1}".to_string()),
            read: false,
            sequence: 1,
            created_at: "2026-01-01 00:00:00".to_string(),
            delivered_at: None,
            run_id: None,
            workspace_id: None,
            task_id: None,
            dispatch_id: None,
            state: "queued".to_string(),
            expires_at: None,
            obsolete_at: None,
            reply_to_id: None,
            external_meta: None,
        }
    }

    #[test]
    fn banner_includes_metadata_and_reply_hint() {
        let banner = format_message_banner(&message(OrchestrationMessagePriority::Urgent));
        assert!(banner.contains("From: TERM_A (term_a) [URGENT] (status)"));
        assert!(banner.contains("Subject: Build done"));
        assert!(banner.contains("All green."));
        assert!(banner.contains("[Payload: {\"x\":1}]"));
        assert!(banner.contains("alera orchestration reply --id msg_1"));
    }

    #[test]
    fn normal_priority_has_no_tag() {
        let banner = format_message_banner(&message(OrchestrationMessagePriority::Normal));
        assert!(banner.contains("From: TERM_A (term_a) (status)"));
    }

    #[test]
    fn injection_wrapper_counts_messages() {
        let batch = [
            message(OrchestrationMessagePriority::Normal),
            message(OrchestrationMessagePriority::High),
        ];
        let formatted = format_messages_for_injection(&batch);
        assert!(formatted.starts_with("\n--- Orchestration Messages (2) ---\n"));
        assert!(formatted.ends_with("\n---\n"));
    }

    #[test]
    fn empty_batch_formats_to_empty_string() {
        assert!(format_messages_for_injection(&[]).is_empty());
    }

    #[test]
    fn oversized_body_is_truncated_on_utf8_boundary() {
        let mut oversized = message(OrchestrationMessagePriority::Normal);
        oversized.body = "á".repeat(INJECT_BODY_MAX_BYTES);
        let banner = format_message_banner(&oversized);
        assert!(banner.contains("Message body truncated"));
        assert!(banner.len() < oversized.body.len());
    }

    #[test]
    fn injection_batch_is_bounded() {
        let mut oversized = message(OrchestrationMessagePriority::Normal);
        oversized.body = "x".repeat(INJECT_BODY_MAX_BYTES * 2);
        let batch = vec![oversized; 8];
        let formatted = format_messages_for_injection(&batch);
        assert!(formatted.len() <= INJECT_BATCH_MAX_BYTES);
        assert!(formatted.contains("additional message(s) omitted"));
    }

    #[test]
    fn inbox_questions_tell_the_agent_the_sender_cannot_see_the_terminal() {
        let mut question = message(OrchestrationMessagePriority::High);
        question.from_handle = "ext:user".to_string();
        question.external_meta = Some(serde_json::json!({"origin": {"surface": "mobile"}}));
        let banner = format_message_banner(&question);
        assert!(banner.starts_with("──── External question from ext:user via Alera mobile [HIGH]"));
        assert!(banner.contains("The sender cannot read this terminal"));
        assert!(banner.contains("alera orchestration reply --id msg_1 --body \"...\""));
        assert!(banner.contains("--body-file <path>"));
        assert!(!banner.contains("<<'EOF'"));
        assert!(!banner.contains("From: EXT:USER"));
    }

    #[test]
    fn mcp_questions_name_the_client_that_asked() {
        let mut question = message(OrchestrationMessagePriority::High);
        question.from_handle = "ext:mcp".to_string();
        question.external_meta = Some(serde_json::json!({
            "origin": {"surface": "mcp", "transport": "remote", "clientId": "c-1", "clientName": "Chat\u{7}GPT"},
        }));
        let banner = format_message_banner(&question);
        assert!(banner.starts_with("──── External question from ext:mcp via ChatGPT (MCP) [HIGH]"));
        question.external_meta = Some(serde_json::json!({"origin": {"surface": "mcp"}}));
        let banner = format_message_banner(&question);
        assert!(banner.starts_with("──── External question from ext:mcp via an MCP client (MCP)"));
    }

    #[test]
    fn injected_count_keeps_whole_messages_within_one_paste() {
        let mut oversized = message(OrchestrationMessagePriority::Normal);
        oversized.body = "x".repeat(INJECT_BODY_MAX_BYTES * 2);
        let batch = vec![oversized; 8];
        let count = injected_message_count(&batch);
        assert!((1..8).contains(&count));
        let formatted = format_messages_for_injection(&batch[..count]);
        assert!(!formatted.contains("omitted"));
        assert_eq!(injected_message_count(&[]), 0);
        let small = vec![message(OrchestrationMessagePriority::Normal); 3];
        assert_eq!(injected_message_count(&small), 3);
    }
}
