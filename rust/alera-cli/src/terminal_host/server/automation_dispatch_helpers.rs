use alera_core::runtime::{
    redact_known_patterns, AutomationDefinition, AutomationRun, RuntimeStore, LOCAL_HOST_ID,
};

use super::AUTOMATION_PRECHECK_OUTPUT_BYTES;

pub(crate) fn automation_prompt(
    prompt: &str,
    run_id: &str,
    heartbeat_interval_seconds: i64,
) -> String {
    format!(
        "{prompt}\n\nAutomation run context: `alera automation context --run {run_id}`. Send `alera automation heartbeat --run {run_id}` at least every {heartbeat_interval_seconds} seconds while working and finish exactly once with `alera automation complete --run {run_id} --status success|failure|blocked --summary \"...\"`.",
        prompt = prompt,
        run_id = run_id,
        heartbeat_interval_seconds = heartbeat_interval_seconds,
    )
}

pub(crate) fn render_workspace_name(
    template: &str,
    definition: &AutomationDefinition,
    run: &AutomationRun,
) -> String {
    let mut name = template.to_string();
    name = name.replace("{{automation.slug}}", &definition.slug);
    let run_number = run.number.to_string();
    name = name.replace("{{run.number}}", &run_number);
    let normalized = name
        .chars()
        .map(|value| {
            if value.is_ascii_alphanumeric() || matches!(value, '-' | '_' | '.') {
                value
            } else {
                '-'
            }
        })
        .collect::<String>();
    let normalized = normalized.trim_matches('-').to_string();
    if normalized.is_empty() {
        format!("auto-{}-{}", definition.slug, run.number)
    } else {
        normalized.chars().take(80).collect()
    }
}

pub(crate) async fn run_precheck_command(
    runtime_store: &RuntimeStore,
    host_id: &str,
    definition: &AutomationDefinition,
    run: &AutomationRun,
    cwd: &str,
) -> Result<bool, String> {
    if host_id != LOCAL_HOST_ID {
        return crate::automation_ssh_precheck::run_remote_precheck(
            runtime_store,
            definition,
            run,
            host_id,
            cwd,
            &crate::ssh_remote::LiveSshRemoteHost,
        )
        .await;
    }
    super::automation_local_precheck::run_local_precheck(runtime_store, definition, run, cwd).await
}

pub(crate) fn bounded_text(bytes: &[u8]) -> String {
    let start = bytes.len().saturating_sub(AUTOMATION_PRECHECK_OUTPUT_BYTES);
    redact_known_patterns(&String::from_utf8_lossy(&bytes[start..]))
}

#[cfg(test)]
mod tests {
    use super::bounded_text;

    #[test]
    fn precheck_output_is_bounded_and_redacted() {
        let mut bytes = vec![b'x'; 20 * 1024];
        bytes.extend_from_slice(b" token=secret-value");
        let output = bounded_text(&bytes);
        assert!(output.len() <= 16 * 1024);
        assert!(!output.contains("secret-value"));
        assert!(output.contains("[redacted]"));
    }
}
