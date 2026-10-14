use super::*;

impl ClaudeProvider {
    pub(super) async fn send_native_turn(
        &mut self,
        input: TurnInput,
    ) -> Result<TurnStartResult, ProviderError> {
        input.validate()?;
        if !input.attachments.is_empty() {
            return Err(ProviderError::Unsupported(
                "Claude Code turns do not support provider attachments".into(),
            ));
        }
        if input.options.keys().any(|key| key != "appUserItemId") {
            return Err(ProviderError::Unsupported(
                "Claude Code turn options are not supported by this adapter".into(),
            ));
        }
        let app_user_item_id = input
            .options
            .get("appUserItemId")
            .map(|value| {
                value
                    .as_str()
                    .filter(|id| !id.trim().is_empty())
                    .map(str::to_owned)
                    .ok_or_else(|| {
                        ProviderError::Validation("appUserItemId must be a nonempty string".into())
                    })
            })
            .transpose()?;
        if input.interaction_mode != InteractionMode::Default {
            return Err(ProviderError::Unsupported(
                "Claude Code per-turn interaction mode is not supported by this adapter".into(),
            ));
        }
        let session = self
            .session
            .clone()
            .ok_or_else(|| ProviderError::InvalidState("session has not started".into()))?;
        if input.thread_id != session.thread_id {
            return Err(ProviderError::Validation(
                "turn threadId does not match session".into(),
            ));
        }
        if session.active_turn_id.is_some()
            || matches!(
                session.status,
                SessionStatus::Running | SessionStatus::Waiting
            )
        {
            return Err(ProviderError::InvalidState(
                "cannot start a Claude turn while another turn is active or awaiting an event"
                    .into(),
            ));
        }
        if self.closed {
            return Err(ProviderError::Closed);
        }
        if let Some(model) = &input.model {
            if session.model.as_deref() != Some(model.as_str()) {
                return Err(ProviderError::Unsupported(
                    "Claude model switching is not enabled by this adapter".into(),
                ));
            }
        }
        if self.client.is_none() {
            return Err(ProviderError::InvalidState(
                "session client is unavailable".into(),
            ));
        }
        let next_turn = self.next_turn + 1;
        let turn_id = format!("turn:claude:{next_turn}");
        let submitted_prompt = input.input.clone();
        let previous_streamed_text_message_ids = self.streamed_text_message_ids.clone();
        let previous_streamed_thinking_message_ids = self.streamed_thinking_message_ids.clone();
        let previous_streamed_text_unscoped = self.streamed_text_unscoped;
        let previous_streamed_thinking_unscoped = self.streamed_thinking_unscoped;
        let previous_stream_message_id = self.stream_message_id.clone();
        let previous_open_items = std::mem::take(&mut self.open_items);
        let previous_stream_items = std::mem::take(&mut self.stream_items);
        let previous_status = session.status;
        let previous_active_turn_id = session.active_turn_id.clone();
        self.streamed_text_message_ids.clear();
        self.streamed_thinking_message_ids.clear();
        self.streamed_text_unscoped = false;
        self.streamed_thinking_unscoped = false;
        self.stream_message_id = None;
        self.open_items = HashMap::new();
        self.stream_items = HashMap::new();
        *self.active_turn_id.lock().await = Some(turn_id.clone());
        if let Some(session) = &mut self.session {
            session.status = SessionStatus::Running;
            session.active_turn_id = Some(turn_id.clone());
        }
        let send_result = self
            .client
            .as_ref()
            .expect("client checked before turn state setup")
            .send_prompt(input.input)
            .await;
        if let Err(error) = send_result {
            *self.active_turn_id.lock().await = previous_active_turn_id.clone();
            self.streamed_text_message_ids = previous_streamed_text_message_ids;
            self.streamed_thinking_message_ids = previous_streamed_thinking_message_ids;
            self.streamed_text_unscoped = previous_streamed_text_unscoped;
            self.streamed_thinking_unscoped = previous_streamed_thinking_unscoped;
            self.stream_message_id = previous_stream_message_id;
            self.open_items = previous_open_items;
            self.stream_items = previous_stream_items;
            if let Some(session) = &mut self.session {
                session.status = previous_status;
                session.active_turn_id = previous_active_turn_id;
            }
            self.pending.lock().await.clear();
            return Err(sdk_error(error));
        }
        self.next_turn = next_turn;
        self.pending_user_prompt = Some(user_messages::UserPromptCorrelation {
            turn_id: turn_id.clone(),
            app_user_item_id,
            text: submitted_prompt,
        });
        let mut payload = json!({});
        if let Some(model) = session.model {
            payload["model"] = Value::String(model);
        }
        self.queue(self.event(
            EventKind::TurnStarted,
            payload.clone(),
            self.raw("turn", payload),
        ));
        Ok(TurnStartResult {
            thread_id: input.thread_id,
            turn_id,
            native_turn_id: None,
        })
    }
}
