use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use super::{ServerActor, ServerCommand};
use crate::terminal_host::host_error::{HostError, HostResult};

#[path = "terminal_pulse_delivery.rs"]
mod delivery;

#[path = "terminal_pulse_configuration.rs"]
mod configuration;

#[path = "terminal_pulse_watcher.rs"]
mod watcher;

#[path = "terminal_pulse_path_identities.rs"]
mod path_identities;

#[cfg(test)]
use watcher::event_is_relevant;
pub(super) use watcher::WorkspacePulseWatcher;

pub(super) const TERMINAL_PULSE_PAYLOAD_KEY: &str = "terminalPulse";
const DEFAULT_DELAY_MS: u64 = 2_000;
const MIN_DELAY_MS: u64 = 100;
const MAX_DELAY_MS: u64 = 3_600_000;
const MAX_INPUT_BYTES: usize = 4_096;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct TerminalPulseConfiguration {
    command: String,
    #[serde(default = "default_append_enter")]
    append_enter: bool,
    #[serde(default = "default_delay_ms")]
    delay_ms: u64,
}

impl Default for TerminalPulseConfiguration {
    fn default() -> Self {
        Self {
            command: "r".to_string(),
            append_enter: true,
            delay_ms: DEFAULT_DELAY_MS,
        }
    }
}

impl TerminalPulseConfiguration {
    fn validate(&self) -> HostResult<()> {
        if self.command.is_empty() {
            return Err(HostError::format("Terminal Pulse input is required."));
        }
        if self.command.len() > MAX_INPUT_BYTES {
            return Err(HostError::format(format!(
                "Terminal Pulse input cannot exceed {MAX_INPUT_BYTES} bytes."
            )));
        }
        if !(MIN_DELAY_MS..=MAX_DELAY_MS).contains(&self.delay_ms) {
            return Err(HostError::format(format!(
                "Terminal Pulse delay must be between {MIN_DELAY_MS} and {MAX_DELAY_MS} ms."
            )));
        }
        Ok(())
    }

    fn input_bytes(&self) -> Vec<u8> {
        let mut bytes = self.command.as_bytes().to_vec();
        if self.append_enter {
            bytes.push(b'\r');
        }
        bytes
    }
}

fn default_append_enter() -> bool {
    true
}

fn default_delay_ms() -> u64 {
    DEFAULT_DELAY_MS
}

struct TerminalPulseRule {
    workspace_id: String,
    session_instance_id: u64,
    configuration: TerminalPulseConfiguration,
    generation: u64,
    pending: bool,
    activated_after_event_sequence: u64,
    active: Arc<AtomicBool>,
}

struct PendingTerminalPulseConfiguration {
    client_id: u64,
    request_id: i64,
    session_id: String,
    workspace_id: String,
    tab_id: String,
    session_instance_id: u64,
    configuration: TerminalPulseConfiguration,
}

#[derive(Default)]
pub(super) struct TerminalPulseManager {
    rules: HashMap<String, TerminalPulseRule>,
    watchers: HashMap<String, WorkspacePulseWatcher>,
    watcher_starts: HashMap<String, u64>,
    pending_configurations: HashMap<String, PendingTerminalPulseConfiguration>,
    next_generation: u64,
}

impl TerminalPulseManager {
    fn reserve_watcher_start(&mut self, workspace_id: &str) -> Option<u64> {
        if self.watchers.contains_key(workspace_id)
            || self.watcher_starts.contains_key(workspace_id)
        {
            return None;
        }
        let generation = self.issue_generation();
        self.watcher_starts
            .insert(workspace_id.to_string(), generation);
        Some(generation)
    }

    fn queue_configuration(
        &mut self,
        pending: PendingTerminalPulseConfiguration,
    ) -> Option<PendingTerminalPulseConfiguration> {
        self.pending_configurations
            .insert(pending.session_id.clone(), pending)
    }

    fn cancel_pending_configuration(
        &mut self,
        session_id: &str,
    ) -> Option<PendingTerminalPulseConfiguration> {
        self.pending_configurations.remove(session_id)
    }

    fn finish_watcher_start(
        &mut self,
        workspace_id: &str,
        generation: u64,
        watcher: WorkspacePulseWatcher,
    ) -> Option<Vec<PendingTerminalPulseConfiguration>> {
        if self.watcher_starts.get(workspace_id) != Some(&generation)
            || watcher.generation() != generation
        {
            return None;
        }
        self.watcher_starts.remove(workspace_id);
        self.watchers.insert(workspace_id.to_string(), watcher);
        Some(self.take_pending_configurations(workspace_id))
    }

    fn fail_watcher_start(
        &mut self,
        workspace_id: &str,
        generation: u64,
    ) -> Option<Vec<PendingTerminalPulseConfiguration>> {
        if self.watcher_starts.get(workspace_id) != Some(&generation) {
            return None;
        }
        self.watcher_starts.remove(workspace_id);
        Some(self.take_pending_configurations(workspace_id))
    }

    fn take_pending_configurations(
        &mut self,
        workspace_id: &str,
    ) -> Vec<PendingTerminalPulseConfiguration> {
        let session_ids = self
            .pending_configurations
            .iter()
            .filter(|(_, pending)| pending.workspace_id == workspace_id)
            .map(|(session_id, _)| session_id.clone())
            .collect::<Vec<_>>();
        session_ids
            .into_iter()
            .filter_map(|session_id| self.pending_configurations.remove(&session_id))
            .collect()
    }

    fn accepts_watcher_command(&self, workspace_id: &str, watcher_generation: u64) -> bool {
        self.watchers
            .get(workspace_id)
            .is_some_and(|watcher| watcher.generation() == watcher_generation)
    }

    fn arm(
        &mut self,
        session_id: String,
        workspace_id: String,
        session_instance_id: u64,
        configuration: TerminalPulseConfiguration,
    ) {
        let generation = self.issue_generation();
        let activated_after_event_sequence = self
            .watchers
            .get(&workspace_id)
            .map_or(0, WorkspacePulseWatcher::current_event_sequence);
        let previous = self.rules.insert(
            session_id,
            TerminalPulseRule {
                workspace_id,
                session_instance_id,
                configuration,
                generation,
                pending: false,
                activated_after_event_sequence,
                active: Arc::new(AtomicBool::new(true)),
            },
        );
        if let Some(previous) = previous {
            previous.active.store(false, Ordering::Release);
        }
    }

    fn remove_unused_watcher(&mut self, workspace_id: &str) {
        if !self
            .rules
            .values()
            .any(|rule| rule.workspace_id == workspace_id)
            && !self
                .pending_configurations
                .values()
                .any(|pending| pending.workspace_id == workspace_id)
        {
            self.watchers.remove(workspace_id);
        }
    }

    pub(super) fn disarm(&mut self, session_id: &str) -> Option<TerminalPulseConfiguration> {
        let rule = self.rules.remove(session_id)?;
        rule.active.store(false, Ordering::Release);
        if !self
            .rules
            .values()
            .any(|candidate| candidate.workspace_id == rule.workspace_id)
        {
            self.watchers.remove(&rule.workspace_id);
        }
        Some(rule.configuration)
    }

    fn fail_workspace(&mut self, workspace_id: &str) -> Vec<TerminalPulseStateChange> {
        self.watchers.remove(workspace_id);
        let changes = self
            .rules
            .iter()
            .filter(|(_, rule)| rule.workspace_id == workspace_id)
            .map(|(session_id, rule)| TerminalPulseStateChange {
                session_id: session_id.clone(),
                configuration: rule.configuration.clone(),
            })
            .collect::<Vec<_>>();
        for change in &changes {
            if let Some(rule) = self.rules.remove(&change.session_id) {
                rule.active.store(false, Ordering::Release);
            }
        }
        changes
    }

    fn is_armed(&self, session_id: &str, session_instance_id: u64) -> bool {
        self.rules
            .get(session_id)
            .is_some_and(|rule| rule.session_instance_id == session_instance_id)
    }

    fn schedule(&mut self, workspace_id: &str, event_sequence: u64) -> Vec<TerminalPulseSchedule> {
        let mut schedules = Vec::new();
        let session_ids = self
            .rules
            .iter_mut()
            .filter_map(|(session_id, rule)| {
                if rule.workspace_id != workspace_id
                    || event_sequence <= rule.activated_after_event_sequence
                {
                    return None;
                }
                rule.activated_after_event_sequence = event_sequence;
                if rule.pending {
                    return None;
                }
                Some(session_id.clone())
            })
            .collect::<Vec<_>>();
        for session_id in session_ids {
            let generation = self.issue_generation();
            let rule = self
                .rules
                .get_mut(&session_id)
                .expect("scheduled Terminal Pulse rule exists");
            rule.pending = true;
            rule.generation = generation;
            schedules.push(TerminalPulseSchedule {
                session_id,
                session_instance_id: rule.session_instance_id,
                generation: rule.generation,
                delay: Duration::from_millis(rule.configuration.delay_ms),
            });
        }
        schedules
    }

    fn issue_generation(&mut self) -> u64 {
        self.next_generation = self.next_generation.wrapping_add(1);
        if self.next_generation == 0 {
            self.next_generation = 1;
        }
        self.next_generation
    }

    fn due_write(
        &self,
        session_id: &str,
        session_instance_id: u64,
        generation: u64,
    ) -> Option<TerminalPulseWrite> {
        let rule = self.rules.get(session_id)?;
        if !rule.pending
            || rule.session_instance_id != session_instance_id
            || rule.generation != generation
        {
            return None;
        }
        Some(TerminalPulseWrite {
            bytes: rule.configuration.input_bytes(),
            active: Arc::clone(&rule.active),
        })
    }

    #[cfg(test)]
    fn due_bytes(
        &self,
        session_id: &str,
        session_instance_id: u64,
        generation: u64,
    ) -> Option<Vec<u8>> {
        self.due_write(session_id, session_instance_id, generation)
            .map(|write| write.bytes)
    }

    fn complete_due(&mut self, session_id: &str, session_instance_id: u64, generation: u64) {
        let observed_event_sequence = self
            .rules
            .get(session_id)
            .and_then(|rule| self.watchers.get(&rule.workspace_id))
            .map_or(0, WorkspacePulseWatcher::current_event_sequence);
        self.complete_due_at_sequence(
            session_id,
            session_instance_id,
            generation,
            observed_event_sequence,
        );
    }

    fn complete_due_at_sequence(
        &mut self,
        session_id: &str,
        session_instance_id: u64,
        generation: u64,
        observed_event_sequence: u64,
    ) {
        let Some(rule) = self.rules.get_mut(session_id) else {
            return;
        };
        if rule.pending
            && rule.session_instance_id == session_instance_id
            && rule.generation == generation
        {
            rule.activated_after_event_sequence = rule
                .activated_after_event_sequence
                .max(observed_event_sequence);
            rule.pending = false;
        }
    }

    fn retry_due(
        &mut self,
        session_id: &str,
        session_instance_id: u64,
        generation: u64,
    ) -> Option<u64> {
        let rule = self.rules.get(session_id)?;
        if !rule.pending
            || rule.session_instance_id != session_instance_id
            || rule.generation != generation
        {
            return None;
        }
        let next_generation = self.issue_generation();
        self.rules
            .get_mut(session_id)
            .expect("retried Terminal Pulse rule exists")
            .generation = next_generation;
        Some(next_generation)
    }
}

struct TerminalPulseStateChange {
    session_id: String,
    configuration: TerminalPulseConfiguration,
}

struct TerminalPulseSchedule {
    session_id: String,
    session_instance_id: u64,
    generation: u64,
    delay: Duration,
}

struct TerminalPulseWrite {
    bytes: Vec<u8>,
    active: Arc<AtomicBool>,
}

impl ServerActor {
    pub(super) async fn terminal_pulse_status(&self, payload: &Value) -> HostResult<Value> {
        let session_id = self.require_session(payload)?;
        let session = self
            .sessions
            .get(&session_id)
            .expect("required session exists");
        let configuration = self.terminal_pulse_configuration(&session.tab_id).await?;
        Ok(terminal_pulse_state(
            configuration,
            self.terminal_pulses
                .is_armed(&session_id, session.instance_id()),
        ))
    }

    async fn terminal_pulse_configuration(
        &self,
        tab_id: &str,
    ) -> HostResult<TerminalPulseConfiguration> {
        let tab = self
            .runtime_store
            .find_workspace_tab(tab_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let Some(value) = tab.and_then(|tab| tab.payload.get(TERMINAL_PULSE_PAYLOAD_KEY).cloned())
        else {
            return Ok(TerminalPulseConfiguration::default());
        };
        serde_json::from_value(value).map_err(|error| HostError::format(error.to_string()))
    }

    async fn persist_terminal_pulse_configuration(
        &self,
        tab_id: &str,
        configuration: &TerminalPulseConfiguration,
    ) -> HostResult<()> {
        let mut tab = self
            .runtime_store
            .find_workspace_tab(tab_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state(format!("terminal tab not found: {tab_id}")))?;
        let payload = tab
            .payload
            .as_object_mut()
            .ok_or_else(|| HostError::format("Terminal tab payload must be an object."))?;
        payload.insert(
            TERMINAL_PULSE_PAYLOAD_KEY.to_string(),
            serde_json::to_value(configuration)
                .map_err(|error| HostError::format(error.to_string()))?,
        );
        tab.updated_at = chrono::Utc::now();
        self.runtime_store
            .upsert_workspace_tab(tab)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        Ok(())
    }
}

fn terminal_pulse_state(configuration: TerminalPulseConfiguration, armed: bool) -> Value {
    json!({
        "configuration": configuration,
        "armed": armed,
    })
}

#[cfg(test)]
#[path = "terminal_pulse_manager_cases.rs"]
mod manager_cases;
#[cfg(test)]
#[path = "terminal_pulse_tests.rs"]
mod tests;
#[cfg(test)]
#[path = "terminal_pulse_watcher_cases.rs"]
mod watcher_cases;
