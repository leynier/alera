//! T3 Code's ACP registry driver lists an available command named `$name` as
//! a skill rather than a slash command (`normalizeAcpRegistryCommands`). The
//! other ACP flavors keep every advertised command a slash command.

use crate::config::AcpFlavor;
use crate::provider::AcpProvider;
use agent_client_protocol::AcpIncoming;
use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{
    EventKind, ProviderError, ProviderEvent, ProviderSkill, ProviderSkillsUpdate,
    ProviderSlashCommand, ProviderSlashCommandsUpdate,
};
use serde_json::Value;
use std::collections::HashSet;

const MAX_NAME_CHARS: usize = 128;
const MAX_DESCRIPTION_CHARS: usize = 1024;
/// Commands and skills share one budget, as in the reference.
const MAX_ACCEPTED: usize = 128;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct RegistryCommands {
    pub commands: ProviderSlashCommandsUpdate,
    pub skills: ProviderSkillsUpdate,
}

/// An opaque value is used as is: blank, padded or overlong ones are dropped
/// instead of repaired.
fn opaque(value: &str) -> Option<&str> {
    (!value.is_empty() && value == value.trim() && value.chars().count() <= MAX_NAME_CHARS)
        .then_some(value)
}

fn bounded(value: Option<&str>) -> Option<String> {
    let value: String = value?.trim().chars().take(MAX_DESCRIPTION_CHARS).collect();
    (!value.is_empty()).then_some(value)
}

/// JavaScript's `encodeURIComponent`, which builds the reference skill path.
fn encode_uri_component(value: &str) -> String {
    let mut encoded = String::with_capacity(value.len());
    for byte in value.bytes() {
        if byte.is_ascii_alphanumeric() || b"-_.!~*'()".contains(&byte) {
            encoded.push(byte as char);
        } else {
            encoded.push_str(&format!("%{byte:02X}"));
        }
    }
    encoded
}

pub(crate) fn registry_commands(update: &Value) -> RegistryCommands {
    let entries = update
        .get("availableCommands")
        .or_else(|| update.get("available_commands"))
        .and_then(Value::as_array)
        .map(Vec::as_slice)
        .unwrap_or_default();
    let mut seen = HashSet::new();
    let mut commands = Vec::new();
    let mut skills = Vec::new();
    let mut accepted = 0;
    for entry in entries {
        let Some(name) = entry.get("name").and_then(Value::as_str).and_then(opaque) else {
            continue;
        };
        if !seen.insert(name.to_lowercase()) {
            continue;
        }
        let description = bounded(entry.get("description").and_then(Value::as_str));
        if let Some(skill_name) = name.strip_prefix('$') {
            let Some(skill_name) = opaque(skill_name) else {
                continue;
            };
            let path = format!("acp://skill/{}", encode_uri_component(skill_name));
            if let Some(skill) = ProviderSkill::from_native(skill_name, &path, true) {
                skills.push(
                    skill
                        .with_description(description.as_deref())
                        .with_scope(Some("agent")),
                );
            }
        } else {
            let hint = bounded(
                entry
                    .get("input")
                    .and_then(|input| input.get("hint"))
                    .and_then(Value::as_str),
            );
            commands.extend(ProviderSlashCommand::from_native(
                name,
                description.as_deref(),
                hint.as_deref(),
            ));
        }
        accepted += 1;
        if accepted == MAX_ACCEPTED {
            break;
        }
    }
    RegistryCommands {
        commands: ProviderSlashCommandsUpdate::new(commands),
        skills: ProviderSkillsUpdate::new(skills),
    }
}

impl<T: JsonTransport> AcpProvider<T> {
    /// The registry split of an `available_commands_update`, read before the
    /// shared mapping consumes the notification.
    pub(crate) fn registry_commands(&self, incoming: &AcpIncoming) -> Option<RegistryCommands> {
        if self.config.flavor != AcpFlavor::Registry {
            return None;
        }
        let AcpIncoming::Notification { params, .. } = incoming else {
            return None;
        };
        let update = params.get("update")?;
        (update.get("sessionUpdate").and_then(Value::as_str) == Some("available_commands_update"))
            .then(|| registry_commands(update))
    }

    /// Narrows the mapped command list to slash commands and queues the
    /// skills after it. Every update replaces both lists, so an empty skill
    /// list still goes out and clears skills an earlier update listed.
    pub(crate) fn publish_registry_commands(
        &mut self,
        event: &mut ProviderEvent,
        split: RegistryCommands,
    ) -> Result<(), ProviderError> {
        if event.kind != EventKind::SessionCommandsUpdated {
            return Ok(());
        }
        event.payload = split.commands.payload();
        let mut skills = event.clone();
        skills.kind = EventKind::SessionSkillsUpdated;
        skills.payload = split.skills.payload();
        self.queue_event(skills)
    }
}

#[cfg(test)]
mod tests {
    use super::encode_uri_component;

    #[test]
    fn encodes_like_encode_uri_component() {
        assert_eq!(encode_uri_component("plugin:deploy"), "plugin%3Adeploy");
        assert_eq!(encode_uri_component("a b/é"), "a%20b%2F%C3%A9");
        assert_eq!(encode_uri_component("ok-_.!~*'()"), "ok-_.!~*'()");
    }
}
