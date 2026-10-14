use super::*;
use alera_provider_protocol::NativeTask;

impl ClaudeProvider {
    pub(super) fn map_native_task(&self, subtype: &str, payload: &Value) -> Vec<ProviderEvent> {
        let raw = self.raw(subtype, payload.clone());
        let Some(task_id) = canonical_payload::task_id(payload).filter(|id| !id.trim().is_empty())
        else {
            return vec![self.event(
                EventKind::RuntimeWarning,
                json!({"message":"Claude task message has no native task id","detail":payload}),
                raw,
            )];
        };
        let native_status =
            canonical_payload::text_field(payload.get("patch").unwrap_or(payload), &["status"])
                .or_else(|| canonical_payload::text_field(payload, &["status"]));
        let status = canonical_payload::task_status(payload.get("patch").unwrap_or(payload))
            .map(str::to_owned)
            .or(native_status.clone());
        let terminal = matches!(
            status.as_deref(),
            Some("completed" | "failed" | "stopped" | "cancelled" | "interrupted")
        );
        let kind = if subtype == "task_notification"
            || terminal
            || subtype.contains("complete")
            || subtype.contains("finish")
        {
            EventKind::TaskCompleted
        } else if subtype.contains("start") {
            EventKind::TaskStarted
        } else if subtype.contains("progress") || subtype.contains("output") {
            EventKind::TaskProgress
        } else {
            EventKind::TaskUpdated
        };
        let task = NativeTask {
            native_task_id: Some(task_id.clone()),
            parent_native_thread_id: canonical_payload::text_field(
                payload,
                &["session_id", "sessionId"],
            ),
            child_native_thread_ids: Vec::new(),
            native_tool_call_id: canonical_payload::text_field(
                payload,
                &["tool_use_id", "toolUseId"],
            ),
            status: native_status,
        };
        let display_status = if kind == EventKind::TaskCompleted
            && matches!(status.as_deref(), Some("cancelled" | "interrupted"))
        {
            Some("stopped".to_owned())
        } else {
            status
        };
        let mut normalized = canonical_payload::compact_nulls(json!({
            "taskId":task_id,
            "description":canonical_payload::text_field(payload, &["description", "title", "command"]),
            "summary":canonical_payload::text_field(payload, &["summary", "output", "message"]),
            "taskType":canonical_payload::text_field(payload, &["task_type", "taskType"]),
            "status":display_status,
            "nativeTask":task,
            "detail":payload,
        }));
        if kind == EventKind::TaskCompleted && normalized.get("status").is_none() {
            normalized["status"] = json!(canonical_payload::completed_task_status(payload));
        }
        vec![self.event(kind, normalized, raw)]
    }
}
