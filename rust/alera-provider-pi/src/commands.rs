//! Pi's composer catalog and its `/compact` builtin, as T3 Code reads them:
//! RPC `get_commands` lists extension commands, prompt templates and skills
//! (`source: "skill"`), but omits the TUI builtins, so `/compact` is
//! advertised here and sent as the RPC `compact` command.

use crate::{provider::PiProvider, rpc};
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{
    EventKind, ProviderError, ProviderEvent, ProviderRefs, ProviderSkill, ProviderSkillsUpdate,
    ProviderSlashCommand, ProviderSlashCommandsUpdate, RequestId,
};
use serde_json::{Map, Value};

/// Outside the numbered call ids, so the catalog request never shifts them.
const COMMANDS_REQUEST_ID: &str = "alera-pi-get-commands";

/// The instructions of a `/compact [instructions]` prompt, `Some(None)` for a
/// bare `/compact`, or `None` for any other text.
pub(crate) fn compact_command(text: &str) -> Option<Option<String>> {
    let rest = text.trim().strip_prefix("/compact")?;
    if rest.is_empty() {
        return Some(None);
    }
    if !rest.starts_with(char::is_whitespace) {
        return None;
    }
    let instructions = rest.trim();
    Some((!instructions.is_empty()).then(|| instructions.to_owned()))
}

fn text<'a>(record: Option<&'a Value>, key: &str) -> Option<&'a str> {
    record?
        .get(key)?
        .as_str()
        .map(str::trim)
        .filter(|value| !value.is_empty())
}

fn skill_scope(scope: Option<&str>) -> Option<&str> {
    match scope?.to_lowercase().as_str() {
        "global" | "personal" => Some("user"),
        "workspace" | "local" => Some("project"),
        _ => scope,
    }
}

fn skill(command: &Value, name: &str) -> Option<ProviderSkill> {
    let name = name.strip_prefix("skill:").unwrap_or(name);
    if name.is_empty() {
        return None;
    }
    let source_info = command.get("sourceInfo");
    let interface = command.get("interface");
    let fallback_path = format!("pi:skill:{name}");
    let path = text(source_info, "path")
        .or_else(|| text(Some(command), "path"))
        .unwrap_or(&fallback_path);
    let display_name = text(Some(command), "displayName")
        .or_else(|| text(source_info, "displayName"))
        .or_else(|| text(interface, "displayName"));
    let short_description = text(Some(command), "shortDescription")
        .or_else(|| text(source_info, "shortDescription"))
        .or_else(|| text(interface, "shortDescription"));
    Some(
        ProviderSkill::from_native(name, path, true)?
            .with_description(text(Some(command), "description"))
            .with_scope(skill_scope(
                text(source_info, "scope").or_else(|| text(Some(command), "location")),
            ))
            .with_display_name(display_name)
            .with_short_description(short_description),
    )
}

/// The `get_commands` data as the composer's slash commands, `/compact`
/// first, and its skills.
pub(crate) fn discovered_commands(
    data: &Value,
) -> (ProviderSlashCommandsUpdate, ProviderSkillsUpdate) {
    let entries = data
        .get("commands")
        .and_then(Value::as_array)
        .map(Vec::as_slice)
        .unwrap_or_default();
    let mut commands: Vec<_> = ProviderSlashCommand::from_native(
        "compact",
        Some("Summarize the conversation and reduce context usage"),
        Some("Optional instructions"),
    )
    .into_iter()
    .collect();
    let mut skills = Vec::new();
    for entry in entries {
        let Some(name) = text(Some(entry), "name") else {
            continue;
        };
        if text(Some(entry), "source") == Some("skill") {
            skills.extend(skill(entry, name));
        } else if name != "compact" {
            commands.extend(ProviderSlashCommand::from_native(
                name,
                text(Some(entry), "description"),
                None,
            ));
        }
    }
    (
        ProviderSlashCommandsUpdate::new(commands),
        ProviderSkillsUpdate::new(skills),
    )
}

impl<T: JsonTransport> PiProvider<T> {
    /// Asks for the catalog without waiting, so a Pi that is slow to answer
    /// never delays the session; the answer is consumed with the other
    /// responses.
    pub(crate) async fn request_commands(&mut self) -> Result<(), ProviderError> {
        let id = RequestId::String(COMMANDS_REQUEST_ID.into());
        self.transport
            .send(rpc::request(&id, "get_commands", Value::Object(Map::new())))
            .await?;
        self.commands_pending = true;
        Ok(())
    }

    /// Queues the catalog events when [message] answers `get_commands`. A
    /// failed read publishes nothing rather than an empty catalog.
    pub(crate) fn consume_commands_response(&mut self, message: &Value) -> bool {
        let answers = match message.get("id") {
            Some(id) => id.as_str() == Some(COMMANDS_REQUEST_ID),
            None => message.get("command").and_then(Value::as_str) == Some("get_commands"),
        };
        if !self.commands_pending || !answers {
            return false;
        }
        self.commands_pending = false;
        let Ok(data) = rpc::response_success(message) else {
            return true;
        };
        let (commands, skills) = discovered_commands(&data);
        for (kind, payload) in [
            (EventKind::SessionCommandsUpdated, commands.payload()),
            (EventKind::SessionSkillsUpdated, skills.payload()),
        ] {
            let mut event = self.event(
                kind,
                payload,
                &RequestId::String(COMMANDS_REQUEST_ID.into()),
                "get_commands",
                message.clone(),
            );
            event.turn_id = None;
            event.provider_refs = Some(ProviderRefs::default());
            self.queued_events.push_back(event);
        }
        true
    }

    /// Starts a `/compact` turn. Pi aborts any running agent first and emits
    /// no `agent_settled` for it, so its response ends the turn.
    pub(crate) async fn send_compact(
        &mut self,
        instructions: Option<String>,
    ) -> Result<(), ProviderError> {
        let fields = instructions
            .map(|instructions| ("customInstructions".to_owned(), Value::String(instructions)));
        self.transport
            .send(rpc::fire_and_forget("compact", fields))
            .await?;
        self.compact_pending = true;
        Ok(())
    }

    /// Settles the `/compact` turn when [message] answers it. A rejection
    /// fails the turn unless a compaction already started, whose own end
    /// reports the outcome, or a stop was requested.
    pub(crate) fn consume_compact_response(&mut self, message: &Value) -> bool {
        if !self.compact_pending
            || message.get("command").and_then(Value::as_str) != Some("compact")
        {
            return false;
        }
        self.compact_pending = false;
        let succeeded = message.get("success").and_then(Value::as_bool) == Some(true);
        if succeeded || self.compaction_seen || self.interrupt_requested {
            // The response has none of the agent fields a settle reads, so it
            // settles as completed or, after a stop request, interrupted.
            self.settle_message = Some(message.clone());
        } else {
            let mut failure = message.clone();
            if failure.get("error").and_then(Value::as_str).is_none() {
                failure["error"] = Value::String("Pi compact failed.".into());
            }
            self.prompt_failure = Some(failure);
        }
        true
    }

    pub(crate) fn observe_compaction(&mut self, message: &Value) {
        if self.compact_pending
            && matches!(
                rpc::record_type(message),
                Some("compaction_start" | "auto_compaction_start")
            )
        {
            self.compaction_seen = true;
        }
    }

    /// The event a consumed response leaves to report, if any.
    pub(crate) async fn after_response(&mut self) -> Result<Option<ProviderEvent>, ProviderError> {
        if let Some(failure) = self.prompt_failure.take() {
            let event = crate::lifecycle::prompt_failed(self, failure);
            self.mark_terminal(false);
            return Ok(Some(event));
        }
        if let Some(event) = self.queued_events.pop_front() {
            return Ok(Some(event));
        }
        self.take_settled().await
    }

    /// The terminal event of a settle that Pi reports idle, keeping the
    /// settle for a later check while Pi is still busy.
    pub(crate) async fn take_settled(&mut self) -> Result<Option<ProviderEvent>, ProviderError> {
        let Some(message) = self.settle_message.take() else {
            return Ok(None);
        };
        let state = self.call("get_state", Value::Object(Map::new())).await?;
        if !crate::runtime::state_is_idle(&state) {
            self.settle_message = Some(message);
            return Ok(None);
        }
        let event = crate::events::agent_settled(self, message)?;
        self.mark_terminal(false);
        Ok(Some(event))
    }
}
