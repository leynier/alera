//! The home CLI terminal: startup, turn injection, readiness, and interrupts.

use std::time::Duration;

use alera_core::runtime::{
    is_voice_home_workspace_id, RuntimeVoiceSettings, VOICE_HOME_WORKSPACE_ID,
};
use serde_json::{json, Value};

use super::voice_realtime::RealtimeClientMessage;
use super::voice_session::{PendingVoiceTurn, VoiceSessionPhase};
use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::orchestration::agent_prompt_injection::{
    build_agent_prompt_paste_bytes, AGENT_PROMPT_SUBMIT,
};
use crate::terminal_host::orchestration::agent_registry::adapter_for;
use crate::terminal_host::orchestration::message_delivery::DEFERRED_ENTER_DELAY_MS;
use crate::terminal_host::protocol::event;
use crate::terminal_host::session::{PtyWriteCompletion, Session};

impl ServerActor {
    /// The home terminal re-reports ready while it idles; only a real state
    /// change may flush its queues. Other terminals keep the old behavior.
    pub(super) fn voice_home_ready_transition(&self, handle: &str, changed: bool) -> bool {
        changed || self.voice.home_session_id.as_deref() != Some(handle)
    }

    pub(super) async fn flush_voice_turns_if_ready(&mut self, session_id: &str) {
        if self.voice.home_session_id.as_deref() != Some(session_id) {
            return;
        }
        if self.voice.home_inject.is_some() {
            return;
        }
        if self.orchestration_delivery_in_flight.contains(session_id) {
            return;
        }
        if let Err(error) = self.flush_voice_turns().await {
            tracing::warn!("voice home turn flush failed: {error}");
            self.voice.last_error = Some(error.to_string());
        }
    }

    pub(super) async fn deliver_home_ready_queues(&mut self, session_id: &str) {
        if self.voice.home_session_id.as_deref() == Some(session_id) {
            self.voice.home_needs_fresh_ready = false;
        }
        let had_startup = self.home_has_pending_startup_prompt(session_id).await;
        self.deliver_pending_agent_prompt(session_id).await;
        if had_startup {
            return;
        }
        if self.voice.home_session_id.as_deref() == Some(session_id)
            && !self.voice.pending_user_turns.is_empty()
        {
            self.flush_voice_turns_if_ready(session_id).await;
            return;
        }
        self.deliver_pending_messages(session_id).await;
        if self.voice.home_session_id.as_deref() == Some(session_id) {
            self.flush_voice_turns_if_ready(session_id).await;
        }
    }

    pub(super) async fn home_has_pending_startup_prompt(&self, session_id: &str) -> bool {
        let Some(session) = self.sessions.get(session_id) else {
            return false;
        };
        if session.initial_agent_prompt_delivered {
            return false;
        }
        let Ok(Some(tab)) = self.runtime_store.find_workspace_tab(&session.tab_id).await else {
            return false;
        };
        tab.payload
            .get("pendingAgentPrompt")
            .and_then(|pending| pending.get("prompt"))
            .and_then(Value::as_str)
            .is_some_and(|prompt| !prompt.is_empty())
    }

    pub(super) fn abandon_home_inject(&mut self, session_id: &str) {
        if self.voice.home_session_id.as_deref() != Some(session_id) {
            return;
        }
        if let Some(inject) = self.voice.home_inject.take() {
            for turn in inject.turns.into_iter().rev() {
                self.voice.pending_user_turns.push_front(turn);
            }
        }
        self.voice.home_needs_fresh_ready = false;
        self.voice.home_session_id = None;
        self.voice.home_tab_id = None;
    }

    pub(super) fn finish_voice_home_inject(
        &mut self,
        session_id: &str,
        session_instance_id: u64,
        generation: u64,
        error: Option<String>,
    ) {
        let Some(inject) = self.voice.home_inject.as_ref() else {
            return;
        };
        let current_instance = self.sessions.get(session_id).map(Session::instance_id);
        if self.voice.home_session_id.as_deref() != Some(session_id)
            || inject.session_instance_id != session_instance_id
            || inject.generation != generation
            || current_instance != Some(session_instance_id)
        {
            return;
        }
        let inject = self.voice.home_inject.take().expect("checked above");
        if let Some(message) = error {
            for turn in inject.turns.into_iter().rev() {
                self.voice.pending_user_turns.push_front(turn);
            }
            self.voice.last_error = Some(message);
            return;
        }
        self.voice.home_needs_fresh_ready = true;
    }

    pub(super) async fn ensure_voice_home(&mut self) -> HostResult<()> {
        let home = self
            .runtime_store
            .ensure_voice_home(&self.runtime_dir)
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        let created = home.created;
        let project_id = home.project.id.clone();
        self.voice.home = Some(home);
        if created {
            self.broadcast_workspaces_changed(Some(&project_id));
        }
        Ok(())
    }

    pub(super) async fn ensure_home_agent(&mut self) -> HostResult<()> {
        self.ensure_voice_home().await?;
        if let Some(session_id) = self.voice.home_session_id.clone() {
            let running = self.sessions.get(&session_id).is_some_and(Session::running);
            if running && !self.voice.home_cli_exited {
                return Ok(());
            }
            self.abandon_home_inject(&session_id);
        }
        if self.voice.home_cli_exited {
            self.voice.home_cli_exited = false;
            self.retire_abandoned_home_sessions().await;
        } else if let Some((tab_id, session_id)) = self.find_running_home_session() {
            self.voice.home_tab_id = Some(tab_id);
            self.voice.home_session_id = Some(session_id);
            return Ok(());
        }
        let profile_id = self.resolve_home_profile_id().await?;
        let response = self
            .launch_agent_profile(
                None,
                &json!({
                    "workspaceId": VOICE_HOME_WORKSPACE_ID,
                    "profileId": profile_id,
                    "prompt": home_agent_startup_prompt(),
                }),
            )
            .await?;
        let tab = response
            .get("tab")
            .ok_or_else(|| HostError::state("voice home launch returned no tab"))?;
        let tab_id = tab
            .get("id")
            .and_then(Value::as_str)
            .ok_or_else(|| HostError::state("voice home launch returned no tab id"))?;
        let session_id = tab
            .get("payload")
            .and_then(|value| value.get("terminalSessionId"))
            .and_then(Value::as_str)
            .unwrap_or(tab_id)
            .to_string();
        self.voice.home_tab_id = Some(tab_id.to_string());
        self.voice.home_session_id = Some(session_id);
        Ok(())
    }

    pub(super) fn find_running_home_session(&self) -> Option<(String, String)> {
        self.sessions.iter().find_map(|(session_id, session)| {
            if session.running() && is_voice_home_workspace_id(&session.workspace_id) {
                Some((session.tab_id.clone(), session_id.clone()))
            } else {
                None
            }
        })
    }

    pub(super) async fn retire_abandoned_home_sessions(&mut self) {
        let mut tab_ids: Vec<String> = self
            .sessions
            .values()
            .filter(|session| is_voice_home_workspace_id(&session.workspace_id))
            .map(|session| session.tab_id.clone())
            .collect();
        tab_ids.sort();
        tab_ids.dedup();
        if tab_ids.is_empty() {
            return;
        }
        for tab_id in &tab_ids {
            self.terminate_sessions_for_tab(tab_id).await;
            if let Err(error) = self.runtime_store.remove_workspace_tab(tab_id).await {
                tracing::error!("failed to retire abandoned voice home tab {tab_id}: {error}");
            }
        }
        self.broadcast_workspace_tabs_changed(Some(VOICE_HOME_WORKSPACE_ID));
    }

    pub(super) async fn resolve_home_profile_id(&self) -> HostResult<String> {
        let settings = self
            .runtime_store
            .voice_settings()
            .await
            .unwrap_or_else(|_| RuntimeVoiceSettings::default());
        if let Some(profile_id) = settings
            .home_agent_profile_id
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            return Ok(profile_id.to_string());
        }
        if let Some(profile_id) = self
            .runtime_store
            .default_agent_profile_id()
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        {
            return Ok(profile_id);
        }
        let profiles = self
            .runtime_store
            .list_agent_profiles()
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        profiles
            .into_iter()
            .next()
            .map(|profile| profile.id)
            .ok_or_else(|| {
                HostError::state("Create an agent profile before starting the voice home agent.")
            })
    }

    pub(super) async fn flush_voice_turns(&mut self) -> HostResult<()> {
        let Some(session_id) = self.voice.home_session_id.clone() else {
            return Ok(());
        };
        if self.voice.pending_user_turns.is_empty() {
            return Ok(());
        }
        if self.voice.home_interrupt_pending {
            self.voice.home_interrupt_pending = false;
            self.interrupt_home_agent(&session_id)?;
        }
        if self.voice.home_inject.is_some() {
            self.voice.phase = VoiceSessionPhase::Thinking;
            return Ok(());
        }
        if self.voice.home_needs_fresh_ready {
            self.voice.phase = VoiceSessionPhase::Thinking;
            return Ok(());
        }
        if self.orchestration_delivery_in_flight.contains(&session_id) {
            self.voice.phase = VoiceSessionPhase::Thinking;
            return Ok(());
        }
        if !self.agent_presence.is_injection_ready(&session_id) {
            self.voice.phase = VoiceSessionPhase::Thinking;
            return Ok(());
        }
        let turns = self.voice.take_ready_turns();
        if turns.is_empty() {
            return Ok(());
        }
        let prompt = compose_home_turns(&turns);
        self.inject_home_prompt(&session_id, &prompt, turns)?;
        self.voice.phase = VoiceSessionPhase::Thinking;
        self.maybe_ack_while_thinking().await;
        Ok(())
    }

    pub(super) async fn maybe_ack_while_thinking(&mut self) {
        let settings = self
            .runtime_store
            .voice_settings()
            .await
            .unwrap_or_else(|_| RuntimeVoiceSettings::default());
        if !settings.ack_while_thinking {
            return;
        }
        let ack = "On it.";
        let utterance = self.voice.enqueue_speak(ack.to_string());
        if let Some(handle) = self.voice.realtime.as_ref() {
            if self.voice.speak_queue.len() == 1 {
                self.voice.expecting_speech = true;
                handle.send(RealtimeClientMessage::Speak {
                    text: utterance.text.clone(),
                    utterance_id: Some(utterance.id),
                });
            }
        }
        self.broadcast_voice_owner(event(
            "voice.utterance",
            json!({
                "id": utterance.id,
                "text": utterance.text,
                "queued": self.voice.speak_queue.len(),
                "realtime": self.voice.realtime.is_some(),
            }),
        ));
        self.broadcast_voice_session().await;
    }

    pub(super) fn interrupt_home_agent(&mut self, session_id: &str) -> HostResult<()> {
        let Some(agent_type) = self
            .agent_presence
            .agent_type(session_id)
            .map(str::to_string)
        else {
            return Ok(());
        };
        if let Some(adapter) = adapter_for(&agent_type) {
            self.queue_orchestration_control(session_id, adapter.interrupt_bytes)?;
        }
        Ok(())
    }

    pub(super) fn inject_home_prompt(
        &mut self,
        session_id: &str,
        prompt: &str,
        turns: Vec<PendingVoiceTurn>,
    ) -> HostResult<()> {
        let bytes = build_agent_prompt_paste_bytes(prompt);
        let session = self.sessions.get_mut(session_id).ok_or_else(|| {
            HostError::state(format!("voice home terminal is not running: {session_id}"))
        })?;
        let session_instance_id = session.instance_id();
        self.voice.home_inject_generation = self.voice.home_inject_generation.saturating_add(1);
        let generation = self.voice.home_inject_generation;
        if let Err(error) = session.queue_write_deferred(
            PtyWriteCompletion::VoiceHomePrompt {
                session_instance_id,
                generation,
            },
            &bytes,
            Duration::from_millis(DEFERRED_ENTER_DELAY_MS),
            AGENT_PROMPT_SUBMIT,
        ) {
            for turn in turns.into_iter().rev() {
                self.voice.pending_user_turns.push_front(turn);
            }
            return Err(error);
        }
        self.voice.home_inject = Some(super::voice_session::VoiceHomeInject {
            session_instance_id,
            generation,
            turns,
        });
        Ok(())
    }
}

pub(super) fn home_agent_startup_prompt() -> String {
    "You are Alera's global voice home agent. Wait for the next spoken turn. Speak to the human only with `alera voice speak --text \"...\"`. Keep those sentences short. Do not patch product code from this folder. Delegate with `alera orchestration delegate`.".to_string()
}

pub(super) fn compose_home_turns(turns: &[PendingVoiceTurn]) -> String {
    let interrupted = turns.iter().any(|turn| turn.cancel_home);
    let body = turns
        .iter()
        .map(|turn| turn.text.as_str())
        .collect::<Vec<_>>()
        .join("\n");
    if interrupted {
        format!(
            "The human interrupted you and did not hear the previous spoken message. Drop that oral plan.\n\n{body}"
        )
    } else {
        body
    }
}
