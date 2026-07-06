use alera_core::runtime::{OrchestrationMessage, OrchestrationMessagePriority};

const BANNER_WIDTH: usize = 60;

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
    let sender_name = message.from_handle.to_uppercase();
    let mut lines = vec![format!(
        "──── From: {sender_name} ({from}){priority_tag} ({message_type}) ────",
        from = message.from_handle,
        message_type = message.message_type.as_str(),
    )];
    lines.push(format!("Subject: {}", message.subject));
    if !message.body.is_empty() {
        lines.push(message.body.clone());
    }
    if let Some(payload) = &message.payload {
        lines.push(format!("[Payload: {payload}]"));
    }
    lines.push(format!(
        "[Reply: alera orchestration reply --id {} --body \"...\"]",
        message.id
    ));
    lines.push("─".repeat(BANNER_WIDTH));
    lines.join("\n")
}

/// Grouping banners under a single wrapper line lets agents detect the
/// message block boundary and parse each banner individually.
pub fn format_messages_for_injection(messages: &[OrchestrationMessage]) -> String {
    if messages.is_empty() {
        return String::new();
    }
    let banners = messages
        .iter()
        .map(format_message_banner)
        .collect::<Vec<_>>()
        .join("\n\n");
    format!(
        "\n--- Orchestration Messages ({}) ---\n{banners}\n---\n",
        messages.len()
    )
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
}
