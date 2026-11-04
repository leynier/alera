//! OpenCode's slash commands as T3 Code lists and recognizes them: the
//! builtin `/compact` first, then the server's commands for the workspace.

use crate::config::OpenCodeGeneration;
use crate::provider::{opencode_kind, OpenCodeProvider};
use alera_provider_protocol::{
    is_mention_space, EventKind, ProviderEvent, ProviderRefs, ProviderSlashCommand,
    ProviderSlashCommandsUpdate,
};
use opencode_agent_sdk::HttpTransport;
use serde_json::Value;
use std::time::Duration;

/// T3 Code's bound on a 1.x command listing.
const LIST_TIMEOUT: Duration = Duration::from_secs(10);

fn compact() -> Option<ProviderSlashCommand> {
    ProviderSlashCommand::from_native(
        "compact",
        Some("Summarize the conversation and reduce context usage"),
        None,
    )
}

fn text<'a>(entry: &'a Value, key: &str) -> Option<&'a str> {
    entry
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
}

/// 1.x entries carry argument `hints`; the ones that stand for skills are
/// left to the skill menu.
fn legacy_commands(entries: &[Value]) -> Vec<ProviderSlashCommand> {
    let listed = entries
        .iter()
        .filter(|entry| entry.get("source").and_then(Value::as_str) != Some("skill"))
        .filter_map(|entry| {
            let hints = entry
                .get("hints")
                .and_then(Value::as_array)
                .map(|hints| {
                    hints
                        .iter()
                        .filter_map(Value::as_str)
                        .collect::<Vec<_>>()
                        .join(" ")
                })
                .unwrap_or_default();
            ProviderSlashCommand::from_native(
                text(entry, "name")?,
                text(entry, "description"),
                Some(&hints),
            )
        });
    compact().into_iter().chain(listed).collect()
}

fn v2_commands(entries: &[Value]) -> Vec<ProviderSlashCommand> {
    let listed = entries.iter().filter_map(|entry| {
        ProviderSlashCommand::from_native(text(entry, "name")?, text(entry, "description"), None)
    });
    compact().into_iter().chain(listed).collect()
}

/// The command name and arguments of a text that opens with `/name`, the
/// reference's `^\/([^\s/]+)(?:\s+([\s\S]*))?$` over the trimmed text.
pub(crate) fn command_of(text: &str) -> Option<(String, String)> {
    let text = text.trim();
    let rest = text.strip_prefix('/')?;
    let name_end = rest
        .find(|character: char| is_mention_space(character) || character == '/')
        .unwrap_or(rest.len());
    let (name, after) = rest.split_at(name_end);
    if name.is_empty() {
        return None;
    }
    if after.is_empty() {
        return Some((name.to_owned(), String::new()));
    }
    let arguments = after.trim_start_matches(is_mention_space);
    // Only white space may follow the name; a slash ends the match.
    (arguments.len() < after.len()).then(|| (name.to_owned(), arguments.to_owned()))
}

impl<T: HttpTransport> OpenCodeProvider<T> {
    /// The command list of the session's workspace. A failed read, or a 2.x
    /// server still scanning a directory it has not served (it lists no
    /// commands then, not even its builtins), publishes nothing.
    pub(crate) async fn commands_event(&mut self) -> Option<ProviderEvent> {
        let entries = tokio::time::timeout(
            LIST_TIMEOUT.min(self.config.request_timeout),
            self.client.list_commands(),
        )
        .await
        .ok()?
        .ok()?;
        let commands = match self.config.generation {
            OpenCodeGeneration::Legacy1 => legacy_commands(&entries),
            OpenCodeGeneration::V2 if entries.is_empty() => return None,
            OpenCodeGeneration::V2 => v2_commands(&entries),
        };
        let mut event = ProviderEvent::new(
            opencode_kind(),
            self.config.provider_instance_id.clone(),
            self.session.as_ref()?.thread_id.clone(),
            EventKind::SessionCommandsUpdated,
            ProviderSlashCommandsUpdate::new(commands).payload(),
            None,
        );
        event.provider_refs = Some(ProviderRefs::default());
        Some(event)
    }

    /// Whether the server lists a command named [name]. A failed or slow
    /// listing counts as unknown, so the text goes out as a prompt.
    pub(crate) async fn knows_command(&mut self, name: &str, timeout: Duration) -> bool {
        match tokio::time::timeout(timeout, self.client.list_commands()).await {
            Ok(Ok(entries)) => entries
                .iter()
                .any(|entry| entry.get("name").and_then(Value::as_str) == Some(name)),
            _ => false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::command_of;

    #[test]
    fn matches_like_the_reference_pattern() {
        let pair = |name: &str, arguments: &str| Some((name.to_owned(), arguments.to_owned()));
        assert_eq!(command_of("  /review  "), pair("review", ""));
        assert_eq!(
            command_of("/review  main\n\nthen fix"),
            pair("review", "main\n\nthen fix")
        );
        assert_eq!(command_of("/a/b"), None);
        assert_eq!(command_of("/"), None);
        assert_eq!(command_of("review"), None);
        assert_eq!(command_of("/init /tmp/x"), pair("init", "/tmp/x"));
    }
}
