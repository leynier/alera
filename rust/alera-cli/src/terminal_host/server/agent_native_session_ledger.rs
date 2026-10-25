use std::path::{Path, PathBuf};

use alera_core::runtime::{AgentNativeSessionRecord, LOCAL_HOST_ID};
use serde_json::{Map, Value};
use tokio::io::{AsyncReadExt, AsyncSeekExt};

use crate::agent_status::AgentHookEvent;
use crate::terminal_host::orchestration::agent_registry::canonical_agent_type;
use crate::terminal_host::orchestration::agent_session_settings::{
    codex_settings_from_rollout_tail, copilot_settings_from_events_tail,
    grok_settings_from_summary, settings_from_hook,
};

use super::ServerActor;

/// How much of a session file is read for its latest settings. The newest
/// turn context always sits at the end, and reading the whole rollout of a
/// long conversation on every turn would be wasted work.
const SESSION_FILE_TAIL_BYTES: u64 = 256 * 1024;

impl ServerActor {
    /// The settings a hook reports, refined from the agent's own session file
    /// when the hook names one. Files are read only at turn boundaries and
    /// only for workspaces on this machine: a relayed hook from a remote host
    /// names paths on that host.
    pub(super) async fn observed_session_settings(
        &self,
        event: &AgentHookEvent,
    ) -> Map<String, Value> {
        let mut settings = settings_from_hook(&event.agent_type, &event.payload);
        if !reads_session_files(event.event_name.as_deref())
            || !self.workspace_is_local(&event.workspace_id).await
        {
            return settings;
        }
        let transcript = event
            .payload
            .get("transcript_path")
            .or_else(|| event.payload.get("transcriptPath"))
            .and_then(Value::as_str)
            .map(PathBuf::from);
        let Some(transcript) = transcript else {
            return settings;
        };
        let from_file = match canonical_agent_type(&event.agent_type) {
            "codex" => read_tail(&transcript)
                .await
                .map(|tail| codex_settings_from_rollout_tail(&tail)),
            "grok" => match transcript.parent() {
                Some(dir) => read_tail(&dir.join("summary.json"))
                    .await
                    .and_then(|summary| {
                        serde_json::from_str::<Value>(&summary)
                            .ok()
                            .map(|summary| grok_settings_from_summary(&summary))
                    }),
                None => None,
            },
            "copilot" => match transcript.parent() {
                Some(dir) => read_tail(&dir.join("events.jsonl"))
                    .await
                    .map(|tail| copilot_settings_from_events_tail(&tail)),
                None => None,
            },
            _ => None,
        };
        settings.extend(from_file.unwrap_or_default());
        settings
    }

    async fn workspace_is_local(&self, workspace_id: &str) -> bool {
        matches!(
            self.runtime_store.find_workspace(workspace_id).await,
            Ok(Some(workspace)) if workspace.host_id == LOCAL_HOST_ID
        )
    }

    #[allow(clippy::too_many_arguments)]
    pub(super) async fn record_workspace_native_session(
        &self,
        workspace_id: &str,
        tab_id: &str,
        agent_type: &str,
        session_id: &str,
        ccs_profile: Option<&str>,
        cwd: Option<&str>,
        settings: &Map<String, Value>,
    ) {
        let now = chrono::Utc::now();
        let record = AgentNativeSessionRecord {
            workspace_id: workspace_id.to_string(),
            agent_type: canonical_agent_type(agent_type).to_string(),
            session_id: session_id.to_string(),
            ccs_profile: ccs_profile.map(str::to_string),
            cwd: cwd.filter(|cwd| !cwd.is_empty()).map(str::to_string),
            tab_id: Some(tab_id.to_string()),
            settings: (!settings.is_empty()).then(|| Value::Object(settings.clone())),
            first_seen_at: now,
            last_seen_at: now,
        };
        if let Err(error) = self
            .runtime_store
            .record_agent_native_session(&record)
            .await
        {
            tracing::warn!(%error, workspace_id, agent_type, "could not record agent session");
        }
    }
}

fn reads_session_files(event_name: Option<&str>) -> bool {
    matches!(
        event_name,
        Some("SessionStart" | "UserPromptSubmit" | "Stop" | "stop" | "agentStop" | "sessionStart")
    )
}

async fn read_tail(path: &Path) -> Option<String> {
    let mut file = tokio::fs::File::open(path).await.ok()?;
    let length = file.metadata().await.ok()?.len();
    let start = length.saturating_sub(SESSION_FILE_TAIL_BYTES);
    file.seek(std::io::SeekFrom::Start(start)).await.ok()?;
    let mut bytes = Vec::new();
    file.read_to_end(&mut bytes).await.ok()?;
    let text = String::from_utf8_lossy(&bytes);
    // A tail that starts mid-file starts mid-line; drop that partial line.
    Some(if start > 0 {
        text.split_once('\n')
            .map(|(_, rest)| rest.to_string())
            .unwrap_or_default()
    } else {
        text.into_owned()
    })
}
