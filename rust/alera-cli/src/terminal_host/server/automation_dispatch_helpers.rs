use std::process::Stdio;

use alera_core::child_process::windowless_async_command;
use alera_core::runtime::{
    redact_known_patterns, AutomationDefinition, AutomationPrecheck, AutomationRun, RuntimeStore,
    LOCAL_HOST_ID,
};
use tokio::io::AsyncReadExt;
use tokio::time::timeout;

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
    precheck: &alera_core::runtime::AutomationPrecheck,
    cwd: &str,
) -> Result<bool, String> {
    if host_id != LOCAL_HOST_ID {
        let target = runtime_store
            .find_ssh_target(host_id)
            .await
            .map_err(|error| error.to_string())?
            .ok_or_else(|| format!("SSH target is missing: {host_id}"))?;
        let platform = target
            .runtime_platform
            .as_deref()
            .or(target.platform.as_deref())
            .unwrap_or("linux");
        return crate::automation_ssh_precheck::run_remote_precheck(
            &target, platform, precheck, cwd,
        )
        .await;
    }
    run_local_precheck(precheck, cwd).await
}

async fn run_local_precheck(precheck: &AutomationPrecheck, cwd: &str) -> Result<bool, String> {
    let (program, args) = if cfg!(windows) {
        (
            "cmd.exe",
            vec!["/d".to_string(), "/c".to_string(), precheck.command.clone()],
        )
    } else {
        ("/bin/sh", vec!["-c".to_string(), precheck.command.clone()])
    };
    let mut child = windowless_async_command(program)
        .args(args)
        .current_dir(cwd)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| error.to_string())?;
    let mut stdout_pipe = child.stdout.take();
    let mut stderr_pipe = child.stderr.take();
    let status = match timeout(
        std::time::Duration::from_secs(precheck.timeout_seconds as u64),
        child.wait(),
    )
    .await
    {
        Ok(Ok(status)) => status,
        Ok(Err(error)) => return Err(error.to_string()),
        Err(_) => {
            let _ = child.kill().await;
            let _ = child.wait().await;
            return Err("automation precheck timed out".to_string());
        }
    };
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();
    if let Some(pipe) = stdout_pipe.as_mut() {
        let _ = pipe.read_to_end(&mut stdout).await;
    }
    if let Some(pipe) = stderr_pipe.as_mut() {
        let _ = pipe.read_to_end(&mut stderr).await;
    }
    let stdout = bounded_text(&stdout);
    let stderr = bounded_text(&stderr);
    if !status.success() {
        tracing::info!("automation precheck failed: stdout={stdout:?} stderr={stderr:?}");
    }
    Ok(status.success())
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
