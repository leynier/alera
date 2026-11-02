//! AI titles of a chat (`agentChatTitleGenerationV1`): one automatic attempt
//! when the first turn ends, regeneration on request, and the rule that a
//! generated title never replaces one a person set unless a person asked.

use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::super::agent_chat_title_jobs::{spawn_chat_title_job, ChatTitleJob};
use super::commands::conflict;
use super::header::{Header, TitleGeneration};
use super::ids::new_id;
use super::session::ChatSession;
use super::wire::json as to_json;

/// Title sources a generated title may replace on its own.
const REPLACEABLE_SOURCES: [&str; 3] = ["default", "derived", "generated"];

/// A `generating` state names a job of the process that stopped.
pub(super) fn forget_stale_job(header: &mut Header) {
    if let Some(state) = header
        .title_generation
        .as_mut()
        .filter(|state| state.is_generating())
    {
        state.status = "idle".into();
        state.mode = None;
        state.job_id = None;
        state.replace_user_title = false;
    }
}

pub(super) fn fork_source_title(metadata: Option<&Value>) -> Option<String> {
    metadata?
        .get("forkedFromTitle")?
        .as_str()
        .map(str::to_owned)
}

impl ChatSession {
    /// Before the turn-end flush: decides the one automatic attempt of a new
    /// chat and records it in the header, so the snapshot that ends the turn
    /// already carries it. Spawn the returned job after that flush, so it
    /// reads the finished turn. Older chats without title state are never
    /// renamed by a later setting.
    pub(super) async fn prepare_auto_title(&mut self) -> Option<ChatTitleJob> {
        let generator = self.deps.titles.clone()?;
        if self.header.archived
            || !matches!(self.header.title_source.as_str(), "default" | "derived")
        {
            return None;
        }
        let mut state = match &self.header.title_generation {
            Some(state) if state.auto_attempted || state.is_generating() => return None,
            Some(state) => state.clone(),
            None if self.header.turns.len() <= 1 => TitleGeneration::default(),
            None => return None,
        };
        state.auto_attempted = true;
        if !generator.automatic_enabled().await {
            state.status = "idle".into();
            self.header.title_generation = Some(state);
            return None;
        }
        Some(self.mark_title_job(state, "auto", false))
    }

    pub(super) async fn regenerate_title(&mut self, replace_user_title: bool) -> HostResult<Value> {
        if self.deps.titles.is_none() {
            return Err(conflict("unsupported", "AI chat titles are unavailable."));
        }
        if let Some(state) = self
            .header
            .title_generation
            .as_mut()
            .filter(|state| state.is_generating())
        {
            // The running job serves this request too; a person's request
            // lets its title replace theirs.
            state.replace_user_title |= replace_user_title;
            state.mode = Some("regenerate".into());
            return Ok(json!({"titleGeneration": to_json(&*state)}));
        }
        if self.header.title_source == "user" && !replace_user_title {
            return Err(conflict(
                "titleSetByUser",
                "A person set this chat's title. Only a person can regenerate it.",
            ));
        }
        if self.never_sent() {
            return Err(conflict(
                "noConversation",
                "Send a message before generating a title.",
            ));
        }
        let state = self.header.title_generation.clone().unwrap_or_default();
        self.start_title_job(state, "regenerate", replace_user_title);
        Ok(json!({"titleGeneration": to_json(&self.header.title_generation)}))
    }

    fn start_title_job(&mut self, state: TitleGeneration, mode: &str, replace_user_title: bool) {
        let job = self.mark_title_job(state, mode, replace_user_title);
        self.spawn_title_job(job);
    }

    /// Records a `generating` state for a new job and describes that job.
    fn mark_title_job(
        &mut self,
        mut state: TitleGeneration,
        mode: &str,
        replace_user_title: bool,
    ) -> ChatTitleJob {
        let job_id = new_id("title");
        state.status = "generating".into();
        state.mode = Some(mode.into());
        state.job_id = Some(job_id.clone());
        state.replace_user_title = replace_user_title;
        state.error_message = None;
        self.header.title_generation = Some(state);
        let fork = self
            .fork_source_turn_id
            .clone()
            .map(|turn_id| (self.fork_source_title.clone().unwrap_or_default(), turn_id));
        ChatTitleJob {
            chat_id: self.header.chat_id.clone(),
            job_id,
            previous_title: (mode == "regenerate").then(|| self.header.title.clone()),
            fork,
        }
    }

    pub(super) fn spawn_title_job(&mut self, job: ChatTitleJob) {
        let Some(generator) = self.deps.titles.clone() else {
            return;
        };
        self.cancel_title_job();
        self.title_job_cancel = Some(spawn_chat_title_job(
            job,
            self.deps.store.clone(),
            generator,
            self.mailbox.clone(),
        ));
    }

    /// Stops the running job; its answer, if any, no longer applies.
    pub(super) fn cancel_title_job(&mut self) {
        if let Some(cancel) = self.title_job_cancel.take() {
            let _ = cancel.send(());
        }
    }

    /// A person renamed the chat or closed it: drop the pending job.
    pub(super) fn abandon_title_job(&mut self) {
        self.cancel_title_job();
        if let Some(state) = self.header.title_generation.as_mut() {
            if state.is_generating() {
                state.status = "idle".into();
                state.mode = None;
                state.job_id = None;
                state.replace_user_title = false;
            }
        }
    }

    pub(super) async fn apply_generated_title(
        &mut self,
        job_id: &str,
        result: Result<String, String>,
    ) -> HostResult<Value> {
        let Some(state) = self
            .header
            .title_generation
            .clone()
            .filter(|state| state.is_generating() && state.job_id.as_deref() == Some(job_id))
        else {
            return Ok(json!({"applied": false}));
        };
        self.title_job_cancel = None;
        let mut next = state.clone();
        next.status = "idle".into();
        next.mode = None;
        next.job_id = None;
        next.replace_user_title = false;
        let title = match result {
            Ok(title) => title.trim().chars().take(200).collect::<String>(),
            Err(message) => {
                next.status = "failed".into();
                next.error_message = Some(message.chars().take(500).collect());
                self.header.title_generation = Some(next);
                return Ok(json!({"applied": false}));
            }
        };
        self.header.title_generation = Some(next);
        let replaceable = REPLACEABLE_SOURCES.contains(&self.header.title_source.as_str())
            || state.replace_user_title;
        if !replaceable || title.is_empty() {
            return Ok(json!({"applied": false}));
        }
        Ok(self.set_generated_title(title).await)
    }

    /// A bound agent names its chat: never over a person's title.
    pub(super) async fn rename_by_agent(&mut self, title: String) -> HostResult<Value> {
        if self.header.title_source == "user" {
            return Err(conflict(
                "titleSetByUser",
                "A person set this chat's title. Only a person can change it.",
            ));
        }
        let title = title.trim().chars().take(200).collect::<String>();
        if title.is_empty() {
            return Err(HostError::format("title must not be empty"));
        }
        self.abandon_title_job();
        Ok(self.set_generated_title(title).await)
    }

    async fn set_generated_title(&mut self, title: String) -> Value {
        self.header.title_source = "generated".into();
        if title != self.header.title {
            self.header.title = title.clone();
            if !self.header.archived {
                if let Ok(Some(workspace_id)) =
                    self.deps.tabs.rename_tab(&self.header.tab_id, &title).await
                {
                    self.notify_tabs(workspace_id);
                }
            }
            self.notify_chats();
        }
        json!({"applied": true, "title": title})
    }
}
