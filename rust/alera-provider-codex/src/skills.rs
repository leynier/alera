//! Codex skills through the app-server's `skills/list`, parsed as T3 Code's
//! `parseCodexSkillsListResponse` does, for live sessions and for probes.

use crate::config::CodexProviderConfig;
use crate::provider::CodexProvider;
use crate::wire;
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{
    normalize_skills, EventKind, Provider, ProviderError, ProviderEvent, ProviderKind,
    ProviderSkill, ProviderSkillsUpdate, RawEvent,
};
use serde_json::{json, Value};
use std::path::Path;
use std::time::Duration;

/// Skills are an enrichment, so a slow listing gives up well before the
/// general request timeout would.
const SKILLS_TIMEOUT_CAP: Duration = Duration::from_secs(10);

impl<T: JsonTransport> CodexProvider<T> {
    /// The skills Codex offers in [cwd], initializing the connection first
    /// when needed.
    pub async fn list_skills(&mut self, cwd: &Path) -> Result<Vec<ProviderSkill>, ProviderError> {
        self.initialize().await?;
        let timeout = self.config.request_timeout;
        self.list_skills_within(cwd, timeout)
            .await
            .map(|(skills, _)| skills)
    }

    async fn list_skills_within(
        &mut self,
        cwd: &Path,
        timeout: Duration,
    ) -> Result<(Vec<ProviderSkill>, Value), ProviderError> {
        let cwd = cwd.to_string_lossy().into_owned();
        let id = self
            .send_request("skills/list", json!({ "cwds": [cwd] }))
            .await?;
        let response = match self.await_response(id, "skills/list", timeout).await {
            Err(error @ ProviderError::Timeout { .. }) => {
                // A late answer must not read as an unsolicited response.
                self.abandoned_responses.insert(id);
                return Err(error);
            }
            other => other?,
        };
        Ok((parse_skills_list(&response, &cwd)?, response))
    }

    /// Lists the session's skills and queues `session.skills.updated`. A
    /// failure only leaves the list unannounced.
    pub(crate) async fn queue_session_skills(&mut self) {
        self.skills_stale = false;
        let Some(cwd) = self
            .session
            .as_ref()
            .and_then(|session| session.cwd.clone())
        else {
            return;
        };
        let timeout = self.config.request_timeout.min(SKILLS_TIMEOUT_CAP);
        let Ok((skills, response)) = self.list_skills_within(&cwd, timeout).await else {
            return;
        };
        let Some(session) = self.session.as_ref() else {
            return;
        };
        let event = ProviderEvent::new(
            ProviderKind::Codex,
            self.config.instance_id.clone(),
            session.thread_id.clone(),
            EventKind::SessionSkillsUpdated,
            ProviderSkillsUpdate::new(skills).payload(),
            Some(RawEvent {
                source: "codex.app-server.response".into(),
                method: Some("skills/list".into()),
                message_type: Some("response".into()),
                payload: response,
            }),
        );
        self.queued_events.push_back(event);
    }

    /// Consumes a `skills/changed` notification, which only invalidates the
    /// list, and a late answer to an abandoned request. Returns whether the
    /// message was consumed.
    pub(crate) fn absorb_skills_message(&mut self, message: &Value) -> bool {
        match wire::method(message) {
            Some("skills/changed") if message.get("id").is_none() => {
                self.skills_stale = true;
                true
            }
            Some(_) => false,
            None => message
                .get("id")
                .and_then(Value::as_i64)
                .is_some_and(|id| self.abandoned_responses.remove(&id)),
        }
    }
}

/// The skills Codex offers in `config.cwd`, from a short-lived app-server
/// that is closed again on every outcome.
pub async fn probe_skills(
    config: CodexProviderConfig,
) -> Result<Vec<ProviderSkill>, ProviderError> {
    let cwd = config.cwd.clone().ok_or_else(|| {
        ProviderError::Validation("probing Codex skills requires a working directory".into())
    })?;
    let deadline = config.request_timeout.min(SKILLS_TIMEOUT_CAP);
    let mut provider = None;
    let listed = tokio::time::timeout(deadline, async {
        let provider = provider.insert(CodexProvider::spawn(config).await?);
        provider.list_skills(&cwd).await
    })
    .await
    .unwrap_or_else(|_| {
        Err(ProviderError::Timeout {
            operation: "skills/list".into(),
        })
    });
    let closed = match provider.as_mut() {
        Some(provider) => provider.close().await,
        None => Ok(()),
    };
    let skills = listed?;
    closed?;
    Ok(skills)
}

/// The skills of the entry for [cwd], or of every entry when none matches.
pub(crate) fn parse_skills_list(
    response: &Value,
    cwd: &str,
) -> Result<Vec<ProviderSkill>, ProviderError> {
    let entries = response
        .get("data")
        .and_then(Value::as_array)
        .ok_or_else(|| ProviderError::Protocol("Codex skills/list response has no data".into()))?;
    let entry_skills = |entry: &Value| {
        entry
            .get("skills")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default()
    };
    let skills = match entries
        .iter()
        .find(|entry| entry.get("cwd").and_then(Value::as_str) == Some(cwd))
    {
        Some(entry) => entry_skills(entry),
        None => entries.iter().flat_map(entry_skills).collect(),
    };
    Ok(normalize_skills(skills.iter().filter_map(parse_skill)))
}

fn parse_skill(skill: &Value) -> Option<ProviderSkill> {
    let text = |value: &Value, key: &str| value.get(key).and_then(Value::as_str).map(str::to_owned);
    let interface = skill.get("interface").filter(|value| value.is_object());
    // `??` semantics: an empty top-level text still shadows the interface's.
    let short_description = text(skill, "shortDescription")
        .or_else(|| interface.and_then(|interface| text(interface, "shortDescription")));
    let display_name = interface.and_then(|interface| text(interface, "displayName"));
    let enabled = skill.get("enabled").and_then(Value::as_bool)?;
    Some(
        ProviderSkill::from_native(&text(skill, "name")?, &text(skill, "path")?, enabled)?
            .with_description(text(skill, "description").as_deref())
            .with_scope(text(skill, "scope").as_deref())
            .with_display_name(display_name.as_deref())
            .with_short_description(short_description.as_deref()),
    )
}
