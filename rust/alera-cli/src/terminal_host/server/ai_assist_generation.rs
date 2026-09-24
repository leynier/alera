use std::time::Duration;

use alera_core::runtime::RuntimeAiAssistSettings;
use tokio::sync::oneshot;
use uuid::Uuid;

use crate::terminal_host::host_error::HostResult;

use super::ai_assist_opencode_go::{complete_opencode_go, OPENCODE_GO_LABEL};
use super::ai_assist_requests::{is_opencode_go_agent, plan_command, resolved_model, run_command};

pub(super) async fn complete_configured_opencode_go(
    settings: &RuntimeAiAssistSettings,
    operation: &str,
    prompt: &str,
    session_id: &str,
    cancel_rx: oneshot::Receiver<()>,
) -> HostResult<(String, String)> {
    let model = resolved_model(settings, operation);
    let text = complete_opencode_go(
        prompt,
        &model,
        session_id,
        Duration::from_secs(settings.timeout_seconds.max(1)),
        cancel_rx,
    )
    .await?;
    Ok((text, OPENCODE_GO_LABEL.to_string()))
}

pub(super) async fn generate_ai_assist_output(
    settings: &RuntimeAiAssistSettings,
    operation: &str,
    prompt: &str,
    working_directory: &str,
    cancel_rx: oneshot::Receiver<()>,
) -> HostResult<(String, String)> {
    if is_opencode_go_agent(settings, operation) {
        return complete_configured_opencode_go(
            settings,
            operation,
            prompt,
            &Uuid::new_v4().to_string(),
            cancel_rx,
        )
        .await;
    }
    let plan = plan_command(settings, operation, prompt)?;
    let label = plan.label.clone();
    let output = run_command(plan, working_directory, settings.timeout_seconds, cancel_rx).await?;
    Ok((output, label))
}
