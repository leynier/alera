//! Slash commands a provider advertises for its composer, in the shape of T3
//! Code's `ServerProviderSlashCommand`: a name, an optional description and an
//! optional hint for what to type after it. The provider expands them itself
//! when a prompt starts with `/name`, so clients only insert the text.

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

/// More than any provider lists today; a runaway list stays bounded on the wire.
pub const MAX_PROVIDER_SLASH_COMMANDS: usize = 200;
const MAX_NAME_CHARS: usize = 64;
const MAX_DESCRIPTION_CHARS: usize = 500;
const MAX_HINT_CHARS: usize = 200;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderSlashCommandInput {
    pub hint: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderSlashCommand {
    /// What follows the slash, such as `compact`.
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub input: Option<ProviderSlashCommandInput>,
}

impl ProviderSlashCommand {
    /// A command from native fields, or `None` for a name that cannot be
    /// typed as one token. A leading slash is dropped and blank texts are
    /// treated as absent.
    pub fn from_native(name: &str, description: Option<&str>, hint: Option<&str>) -> Option<Self> {
        let name = name.trim();
        let name = name.strip_prefix('/').unwrap_or(name);
        if name.is_empty()
            || name.chars().count() > MAX_NAME_CHARS
            || name.chars().any(char::is_whitespace)
        {
            return None;
        }
        Some(Self {
            name: name.to_string(),
            description: bounded_text(description, MAX_DESCRIPTION_CHARS),
            input: bounded_text(hint, MAX_HINT_CHARS)
                .map(|hint| ProviderSlashCommandInput { hint }),
        })
    }
}

fn bounded_text(text: Option<&str>, limit: usize) -> Option<String> {
    let text = text?.trim();
    (!text.is_empty()).then(|| text.chars().take(limit).collect())
}

/// [`ProviderSlashCommand`]s in their first order with one entry per name,
/// compared without case. A later duplicate only fills a description or hint
/// the first one lacked.
pub fn normalize_slash_commands(
    commands: impl IntoIterator<Item = ProviderSlashCommand>,
) -> Vec<ProviderSlashCommand> {
    let mut normalized: Vec<ProviderSlashCommand> = Vec::new();
    for command in commands {
        let key = command.name.to_lowercase();
        if let Some(existing) = normalized
            .iter_mut()
            .find(|existing| existing.name.to_lowercase() == key)
        {
            if existing.description.is_none() {
                existing.description = command.description;
            }
            if existing.input.is_none() {
                existing.input = command.input;
            }
            continue;
        }
        if normalized.len() < MAX_PROVIDER_SLASH_COMMANDS {
            normalized.push(command);
        }
    }
    normalized
}

/// The payload of `session.commands.updated`. Each update replaces the whole
/// list; an empty list means the provider offers none right now.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderSlashCommandsUpdate {
    #[serde(default)]
    pub commands: Vec<ProviderSlashCommand>,
}

impl ProviderSlashCommandsUpdate {
    pub fn new(commands: impl IntoIterator<Item = ProviderSlashCommand>) -> Self {
        Self {
            commands: normalize_slash_commands(commands),
        }
    }

    pub fn payload(&self) -> Value {
        json!({ "commands": self.commands })
    }
}
