//! Accepting a client message: receipts, approval redirects, and whether it
//! starts a turn or waits in the queue.

use alera_core::runtime::{AgentChatReceipt, AgentChatReceiptCheck};
use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::commands::{conflict, unsupported, CallerCtx, SendInput};
use super::ids::receipt_scope;
use super::session::ChatSession;
use super::session_turn_admission::client_message_digest;

const CLIENT_MESSAGE_VERB: &str = "clientMessage";

impl ChatSession {
    fn client_message_scope(&self) -> String {
        receipt_scope(
            &format!("chat:{}", self.header.chat_id),
            CLIENT_MESSAGE_VERB,
        )
    }

    pub(super) async fn send(&mut self, input: SendInput, ctx: &CallerCtx) -> HostResult<Value> {
        self.send_declining(input, &[], ctx).await
    }

    /// Declines [declines] (pending approvals the sender saw) and admits the
    /// message in one actor step, after every check a send can fail.
    pub(super) async fn send_declining(
        &mut self,
        input: SendInput,
        declines: &[String],
        ctx: &CallerCtx,
    ) -> HostResult<Value> {
        if self.header.provider == alera_core::runtime::AGENT_CHAT_UNSELECTED_PROVIDER {
            return Err(conflict(
                "providerRequired",
                "Choose an agent before sending a message.",
            ));
        }
        if input.text.trim().is_empty() && input.attachments.is_empty() {
            return Err(HostError::format("a message needs text or attachments"));
        }
        if self
            .deps
            .store
            .is_agent_chat_message_cancelled(&self.header.chat_id, &input.client_message_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        {
            return Err(conflict(
                "request_resolved",
                "This client message was already cancelled.",
            ));
        }
        let scope = self.client_message_scope();
        let digest = client_message_digest(&input, declines);
        match self
            .deps
            .store
            .check_agent_chat_receipt(&scope, &input.client_message_id, &digest)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        {
            AgentChatReceiptCheck::Replay(response) => return Ok(response),
            AgentChatReceiptCheck::Conflict => return Err(super::session_ops::receipt_conflict()),
            AgentChatReceiptCheck::New => {}
        }
        let effort = input.reasoning_effort.clone().or_else(|| {
            (!input
                .model
                .as_deref()
                .is_some_and(|model| self.header.session.model.as_deref() != Some(model)))
            .then(|| self.header.session.reasoning_effort.clone())
            .flatten()
        });
        let provider = self.header.provider.clone();
        let instance_id = self.header.provider_instance_id.clone();
        let model = input
            .model
            .clone()
            .or_else(|| self.header.session.model.clone());
        self.validate_effort(&provider, &instance_id, model.as_deref(), effort.as_deref())
            .await?;
        if input.delivery == "steer" && !self.live_caps.as_ref().is_some_and(|caps| caps.steer) {
            return Err(unsupported(
                "This provider cannot take input during a running turn.",
            ));
        }
        if !declines.is_empty() {
            self.decline_for_redirect(declines, ctx).await?;
        }
        let client_message_id = input.client_message_id.clone();
        let response = if input.delivery == "steer" {
            self.steer_message(input, ctx).await?
        } else if self.must_queue() {
            self.enqueue(input, ctx)
        } else {
            self.start_turn(input, ctx).await?
        };
        // Recorded once the message itself is committed.
        self.message_receipts.push(AgentChatReceipt {
            caller_scope: scope,
            request_id: client_message_id,
            digest,
            receipt: response.clone(),
        });
        Ok(response)
    }

    /// A turn runs, waits on the user, or earlier messages wait ahead.
    fn must_queue(&self) -> bool {
        self.header.session.active_turn_id.is_some()
            || !self.header.pending_requests.is_empty()
            || !self.header.queue.is_empty()
            || self.deferred_turn.is_some()
    }
}
