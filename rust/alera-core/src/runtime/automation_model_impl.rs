use super::AutomationDefinition;

impl AutomationDefinition {
    pub fn material_fingerprint(&self) -> String {
        serde_json::to_string(&serde_json::json!([
            &self.slug,
            &self.prompt_template,
            &self.project_id,
            &self.schedule,
            &self.target,
            &self.setup_policy,
            &self.cleanup_policy,
            &self.overlap_policy,
            self.queue_cap,
            self.inactivity_timeout_seconds,
            self.heartbeat_interval_seconds,
            self.misfire_grace_seconds,
            &self.misfire_policy,
            self.retry_max_attempts,
            self.retry_backoff_seconds,
            self.circuit_failure_threshold,
            self.circuit_open_seconds,
            &self.precheck,
            self.notify_on_success,
        ]))
        .unwrap_or_default()
    }

    pub fn is_approved(&self) -> bool {
        self.approved_revision == Some(self.revision)
    }
}
