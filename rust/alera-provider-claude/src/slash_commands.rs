//! The slash commands Claude Code offers, for the composer menu. Claude
//! expands a prompt that starts with `/name` itself, so the list is all a
//! client needs.

use super::*;
use alera_provider_protocol::{ProviderSlashCommand, ProviderSlashCommandsUpdate};

impl ClaudeProvider {
    /// Queues the commands the CLI answered `initialize` with, which carry a
    /// description and an argument hint.
    pub(super) fn queue_initialize_commands(&mut self) {
        let Some(info) = self.client.as_ref().and_then(ClaudeClient::server_info) else {
            return;
        };
        let Some(update) = initialize_commands(&info) else {
            return;
        };
        self.described_commands = true;
        let raw = self.raw("initialize", json!({ "commands": info["commands"] }));
        let event = self.event(EventKind::SessionCommandsUpdated, update.payload(), raw);
        self.queue(event);
    }

    /// The bare names `system/init` lists, used only when `initialize` did not
    /// describe any, so a described list is never replaced by names.
    pub(super) fn init_message_commands(&self, payload: &Value) -> Option<ProviderEvent> {
        if self.described_commands {
            return None;
        }
        let names = payload.get("slash_commands")?.as_array()?;
        let update = ProviderSlashCommandsUpdate::new(
            names
                .iter()
                .filter_map(|name| ProviderSlashCommand::from_native(name.as_str()?, None, None)),
        );
        Some(self.event(
            EventKind::SessionCommandsUpdated,
            update.payload(),
            self.raw("init", json!({ "slash_commands": names })),
        ))
    }
}

fn initialize_commands(info: &Value) -> Option<ProviderSlashCommandsUpdate> {
    let commands = info.get("commands")?.as_array()?;
    let update = ProviderSlashCommandsUpdate::new(commands.iter().filter_map(|command| {
        let text = |keys: &[&str]| {
            keys.iter()
                .find_map(|key| command.get(*key).and_then(Value::as_str))
        };
        ProviderSlashCommand::from_native(
            text(&["name"])?,
            text(&["description"]),
            text(&["argumentHint", "argument_hint"]),
        )
    }));
    (!update.commands.is_empty()).then_some(update)
}
