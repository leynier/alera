//! The I/O half of `goal.rs`: waiting out the continuation grace window,
//! pausing a goal Codex did not continue, and Stop while a goal works.

use alera_agent_transport::JsonTransport;
use alera_provider_protocol::{ProviderError, ProviderGoalStatus};
use serde_json::{json, Value};

use crate::provider::CodexProvider;

impl<T: JsonTransport> CodexProvider<T> {
    /// The next message, or `Ok(None)` once the held turn's grace window
    /// ends first. Cancel-safe: the hold stays in place when dropped.
    pub(crate) async fn recv_within_goal_hold(&mut self) -> Result<Option<Value>, ProviderError> {
        let Some(deadline) = self.goal.hold.as_ref().map(|hold| hold.deadline) else {
            return self.transport.recv().await.map_err(ProviderError::from);
        };
        match tokio::time::timeout_at(deadline, self.transport.recv()).await {
            Ok(message) => message.map_err(ProviderError::from),
            Err(_) => {
                self.expire_goal_hold();
                Ok(None)
            }
        }
    }

    /// T3 Code's `pauseUncontinuedGoal`: a goal must not read as active once
    /// its run ends, so the goal is paused before the turn settles. Claiming
    /// the hold first makes a turn Codex starts meanwhile an orphan.
    pub(crate) fn expire_goal_hold(&mut self) {
        let Some(hold) = self.goal.hold.take() else {
            return;
        };
        if self.goal.active() && !self.goal.stopping {
            if let Some(thread) = self
                .session
                .as_ref()
                .map(|session| session.native_thread_id.clone())
            {
                self.defer_goal_pause(&thread);
            }
        }
        self.queued_events.push_back(hold.completion);
    }

    /// Sends the requests decided while reading messages. Their answers are
    /// dropped: the goal notifications and turn events that follow report
    /// what they did.
    pub(crate) async fn flush_goal_requests(&mut self) -> Result<(), ProviderError> {
        for (method, params) in std::mem::take(&mut self.goal.deferred_requests) {
            let id = self.send_request(method, params).await?;
            self.abandoned_responses.insert(id);
        }
        Ok(())
    }

    /// Stop while goal work runs pauses the goal first, as T3 Code's
    /// `resolveGoalStopTarget` does. A turn held for continuation already
    /// ended natively and settles as interrupted; otherwise the newest root
    /// turn is the one to stop, which may be past the one the host named.
    /// Returns the native turn to interrupt, if any is still running.
    pub(crate) async fn stop_goal_work(
        &mut self,
        requested: Option<String>,
    ) -> Result<Option<String>, ProviderError> {
        if !self.goal.working() {
            return Ok(requested);
        }
        if let Some(stopped) = self.goal.activation.as_mut() {
            *stopped = true;
        }
        let thread = self
            .session
            .as_ref()
            .map(|session| session.native_thread_id.clone())
            .ok_or_else(|| ProviderError::InvalidState("start a Codex session first".into()))?;
        if self.goal.active() {
            match self
                .call(
                    "thread/goal/set",
                    json!({ "threadId": thread, "status": "paused" }),
                )
                .await
            {
                Ok(response) => {
                    if let Some(goal) = response.get("goal").and_then(crate::goal::goal_from_codex)
                    {
                        self.set_goal(Some(goal));
                    }
                }
                Err(ProviderError::Closed) => return Err(ProviderError::Closed),
                Err(_) => {
                    // Codex keeps the goal; the orphan rule stops what it
                    // starts next, as when an expired hold's pause fails.
                    if let Some(goal) = self.goal.current.as_mut() {
                        goal.status = ProviderGoalStatus::Paused;
                    }
                    self.goal.stopping = true;
                }
            }
            self.queue_goal_update();
        }
        self.flush_goal_requests().await?;
        if let Some(mut hold) = self.goal.hold.take() {
            hold.completion.payload["state"] = json!("interrupted");
            self.queued_events.push_back(hold.completion);
            return Ok(None);
        }
        Ok(self
            .session
            .as_ref()
            .and_then(|session| session.active_turn_id.clone()))
    }
}
