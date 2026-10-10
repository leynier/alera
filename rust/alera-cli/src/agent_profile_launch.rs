use anyhow::{anyhow, Context, Result};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::agent_profile_commands::{
    ensure_capabilities, list_profiles, print_json, select_profile,
};
use crate::cli::{AgentProfileLaunchArgs, RuntimeDirArgs};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::agent_profile_capabilities::{
    RUNTIME_HOST_AGENT_PROFILE_LAUNCH_IDEMPOTENCY_CAPABILITY,
    RUNTIME_HOST_AGENT_PROFILE_SESSION_RESUME_CAPABILITY,
};
use crate::terminal_host::protocol::RUNTIME_HOST_AGENT_PROFILE_PROMPT_LAUNCH_CAPABILITY;
use crate::workspace_context::resolve_workspace_context;

#[derive(Debug, Clone)]
pub struct AgentProfileLaunchEnvelope {
    pub workspace_id: String,
    pub profile_id: String,
    pub profile_name: String,
    pub agent_type: String,
    pub tab_id: String,
    pub payload: Value,
}

impl AgentProfileLaunchEnvelope {
    pub fn to_value(&self) -> Value {
        json!({
            "workspaceId": self.workspace_id,
            "profileId": self.profile_id,
            "profileName": self.profile_name,
            "agentType": self.agent_type,
            "tabId": self.tab_id,
            "tab": self.payload.get("tab").cloned().unwrap_or(Value::Null),
        })
    }
}

pub async fn run(
    runtime: &RuntimeDirArgs,
    client: &mut RuntimeHostRpcClient,
    args: AgentProfileLaunchArgs,
    json_output: bool,
) -> Result<()> {
    let prompt = args.prompt.read()?;
    let context = resolve_workspace_context(runtime, args.workspace.as_deref()).await?;
    let profile = resolve_selected_profile(client, &args.selector).await?;
    let envelope = launch_profile_request(
        client,
        LaunchRequest {
            workspace_id: &context.workspace_id,
            profile_id: &profile.id,
            profile_name: &profile.name,
            prompt: &prompt,
            resume_session_id: args.prompt.resume_session_id.as_deref(),
        },
        args.client_mutation_id,
    )
    .await?;
    if json_output {
        print_json(&envelope.to_value())?;
    } else {
        println!(
            "agent profile launched: {} in workspace {} (tab {})",
            envelope.profile_name, envelope.workspace_id, envelope.tab_id
        );
    }
    Ok(())
}

pub async fn resolve_selected_profile(
    client: &mut RuntimeHostRpcClient,
    selector: &crate::cli::AgentProfileSelectorArgs,
) -> Result<alera_core::runtime::AgentProfile> {
    let (_, profiles) = list_profiles(client).await?;
    let profile = select_profile(&profiles, selector)?.clone();
    ensure_capabilities(
        client,
        &[RUNTIME_HOST_AGENT_PROFILE_PROMPT_LAUNCH_CAPABILITY],
    )
    .await?;
    Ok(profile)
}

pub async fn launch_profile(
    client: &mut RuntimeHostRpcClient,
    workspace_id: &str,
    profile_id: &str,
    profile_name: &str,
    prompt: &str,
    client_mutation_id: Option<String>,
) -> Result<AgentProfileLaunchEnvelope> {
    launch_profile_request(
        client,
        LaunchRequest {
            workspace_id,
            profile_id,
            profile_name,
            prompt,
            resume_session_id: None,
        },
        client_mutation_id,
    )
    .await
}

/// One launch of a resolved profile. A resume carries no prompt.
pub struct LaunchRequest<'a> {
    pub workspace_id: &'a str,
    pub profile_id: &'a str,
    pub profile_name: &'a str,
    pub prompt: &'a str,
    pub resume_session_id: Option<&'a str>,
}

/// The launch payload. `resumeSessionId` is only sent when set, so a host
/// without session resume sees the payload it always did.
pub fn launch_payload(request: &LaunchRequest<'_>, mutation_id: &str) -> Value {
    let mut payload = json!({
        "workspaceId": request.workspace_id,
        "profileId": request.profile_id,
        "prompt": request.prompt,
        "clientMutationId": mutation_id,
    });
    if let Some(id) = request.resume_session_id {
        payload["resumeSessionId"] = json!(id);
    }
    payload
}

pub async fn launch_profile_request(
    client: &mut RuntimeHostRpcClient,
    request: LaunchRequest<'_>,
    client_mutation_id: Option<String>,
) -> Result<AgentProfileLaunchEnvelope> {
    let mut required = vec![RUNTIME_HOST_AGENT_PROFILE_PROMPT_LAUNCH_CAPABILITY];
    if request.resume_session_id.is_some() {
        required.push(RUNTIME_HOST_AGENT_PROFILE_SESSION_RESUME_CAPABILITY);
    }
    ensure_capabilities(client, &required).await?;
    let idempotent = host_has_capability(
        client,
        RUNTIME_HOST_AGENT_PROFILE_LAUNCH_IDEMPOTENCY_CAPABILITY,
    )
    .await?;
    let request_type = if idempotent {
        "agentProfile.launchIdempotent"
    } else {
        "agentProfile.launch"
    };
    let mutation_id = client_mutation_id
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| Uuid::new_v4().to_string());
    let payload = client
        .request_value(request_type, &launch_payload(&request, &mutation_id))
        .await?;
    let tab_id = payload
        .get("tab")
        .and_then(|tab| tab.get("id"))
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow!("agent profile launch returned no tab id"))?
        .to_string();
    let agent_type = payload
        .get("agentType")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    Ok(AgentProfileLaunchEnvelope {
        workspace_id: request.workspace_id.to_string(),
        profile_id: request.profile_id.to_string(),
        profile_name: request.profile_name.to_string(),
        agent_type,
        tab_id,
        payload,
    })
}

async fn host_has_capability(client: &mut RuntimeHostRpcClient, required: &str) -> Result<bool> {
    let status = client
        .request_value("status.get", &json!({}))
        .await
        .context("could not read runtime host capabilities")?;
    let capabilities = status
        .get("runtimeCapabilities")
        .and_then(Value::as_array)
        .ok_or_else(|| anyhow!("runtime host status did not include capabilities"))?;
    Ok(capabilities
        .iter()
        .any(|capability| capability.as_str() == Some(required)))
}
