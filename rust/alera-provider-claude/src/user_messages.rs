use super::*;
use claude_agent_sdk::UserMessage;

pub(super) struct UserPromptCorrelation {
    pub turn_id: String,
    pub app_user_item_id: Option<String>,
    pub text: String,
}

impl ClaudeProvider {
    pub(super) fn map_user_message(&mut self, message: UserMessage) -> ProviderEvent {
        let native_user_id = message
            .uuid
            .as_deref()
            .filter(|id| {
                uuid::Uuid::parse_str(id).is_ok()
                    && message.raw.get("uuid").and_then(Value::as_str) == Some(*id)
            })
            .map(str::to_owned);
        let main_prompt = message.parent_tool_use_id.is_none()
            && message.tool_use_result.is_none()
            && message.raw.get("isSynthetic").and_then(Value::as_bool) != Some(true);
        let native_session = message
            .raw
            .get("session_id")
            .and_then(Value::as_str)
            .filter(|id| !id.is_empty());
        let input_matches = main_prompt
            && native_user_id.is_some()
            && self.pending_user_prompt.as_ref().is_some_and(|pending| {
                pending.app_user_item_id.is_some()
                    && self
                        .session
                        .as_ref()
                        .and_then(|session| session.active_turn_id.as_deref())
                        == Some(pending.turn_id.as_str())
                    && prompt_text(&message.content).as_deref() == Some(pending.text.as_str())
            });
        if let Some(native) = native_session.filter(|_| input_matches) {
            if self
                .session
                .as_ref()
                .is_some_and(|session| session.native_thread_id.starts_with("pending:"))
            {
                self.set_native_thread(native);
            }
        }
        let session_matches = native_session.is_some_and(|native| {
            self.session.as_ref().is_some_and(|session| {
                session.native_thread_id == native
                    && self.fork_source_native_thread_id.as_deref() != Some(native)
            })
        });
        let correlation_matches = input_matches && session_matches;
        let correlation = if correlation_matches {
            self.pending_user_prompt.take()
        } else {
            None
        };
        let data = serde_json::to_value(&message).unwrap_or(Value::Null);
        let mut event = self.event(
            EventKind::ItemUpdated,
            json!({
                "itemType":"user_message","status":"completed","data":data,
            }),
            self.raw("user", message.raw),
        );
        // Replayed history and tool results cannot claim the current submitted prompt.
        event.turn_id = None;
        if let Some(correlation) = correlation {
            event.payload["nativeUserMessageId"] =
                json!(native_user_id.expect("correlated native UUID"));
            event.turn_id = Some(correlation.turn_id);
            if let Some(id) = correlation.app_user_item_id {
                event.payload["appUserItemId"] = json!(id);
            }
        }
        event
    }
}

pub(super) fn prompt_text(content: &Value) -> Option<String> {
    if let Some(text) = content.as_str() {
        return Some(text.into());
    }
    let blocks = content.as_array()?;
    let mut text = String::new();
    for block in blocks {
        if block.get("type").and_then(Value::as_str) != Some("text") {
            return None;
        }
        text.push_str(block.get("text")?.as_str()?);
    }
    Some(text)
}

#[cfg(test)]
mod tests {
    use super::*;
    use claude_agent_sdk::Message;

    fn provider() -> ClaudeProvider {
        let mut provider = ClaudeProvider::new(ClaudeProviderConfig::default()).unwrap();
        provider.session = Some(ProviderSession {
            provider: ProviderKind::Claude,
            provider_instance_id: "claude".into(),
            thread_id: "app".into(),
            native_thread_id: "native-session".into(),
            status: SessionStatus::Running,
            model: None,
            cwd: None,
            active_turn_id: Some("provider-turn".into()),
        });
        provider.pending_user_prompt = Some(UserPromptCorrelation {
            turn_id: "provider-turn".into(),
            app_user_item_id: Some("original-app-user-item".into()),
            text: "exact prompt".into(),
        });
        provider
    }

    fn observed_user(mut fields: Value) -> UserMessage {
        fields["type"] = json!("user");
        let Message::User(message) = Message::from_value(fields) else {
            panic!("expected parsed user message");
        };
        message
    }

    fn echo() -> Value {
        json!({"uuid":"12345678-1234-4234-8234-123456789abc","session_id":"native-session","parent_tool_use_id":null,
            "message":{"role":"user","content":[{"type":"text","text":"exact prompt"}]}})
    }

    #[test]
    fn exact_native_user_uuid_correlates_original_app_item_without_a_native_item_alias() {
        let mut provider = provider();
        let event = provider.map_user_message(observed_user(echo()));
        assert_eq!(
            event.payload["nativeUserMessageId"],
            "12345678-1234-4234-8234-123456789abc"
        );
        assert_eq!(event.payload["appUserItemId"], "original-app-user-item");
        assert_eq!(event.turn_id.as_deref(), Some("provider-turn"));
        assert!(event.item_id.is_none());
        assert!(event.provider_refs.is_none());
        assert!(provider.pending_user_prompt.is_none());
        assert_eq!(
            event.raw.unwrap().payload["uuid"],
            "12345678-1234-4234-8234-123456789abc"
        );
    }

    #[test]
    fn tool_synthetic_wrong_session_and_wrong_prompt_cannot_supply_checkpoint_identity() {
        for override_fields in [
            json!({"parent_tool_use_id":"tool"}),
            json!({"isSynthetic":true}),
            json!({"session_id":"other-native"}),
            json!({"session_id":null}),
            json!({"uuid":"turn:synthetic"}),
            json!({"message":{"role":"user","content":"different prompt"}}),
            json!({"tool_use_result":{"value":"result"}}),
        ] {
            let mut raw = echo();
            for (key, value) in override_fields.as_object().unwrap() {
                raw[key] = value.clone();
            }
            let mut provider = provider();
            let event = provider.map_user_message(observed_user(raw));
            assert!(event.payload.get("nativeUserMessageId").is_none());
            assert!(event.payload.get("appUserItemId").is_none());
            assert!(event.turn_id.is_none());
            assert!(provider.pending_user_prompt.is_some());
        }
    }

    #[test]
    fn uncorrelated_history_and_mismatched_parsed_uuid_cannot_attach_to_live_turn() {
        let mut provider = provider();
        provider.pending_user_prompt = None;
        let event = provider.map_user_message(observed_user(echo()));
        assert!(event.payload.get("nativeUserMessageId").is_none());
        assert!(event.turn_id.is_none());
        let mut provider = self::provider();
        let mut message = observed_user(echo());
        message.uuid = Some("87654321-4321-4321-8321-cba987654321".into());
        let event = provider.map_user_message(message);
        assert!(event.payload.get("nativeUserMessageId").is_none());
    }
}
