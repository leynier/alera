use super::canonical_payload::*;
use super::*;
use claude_agent_sdk::{AssistantMessage, ContentBlock, StreamEvent};

impl ClaudeProvider {
    pub(crate) fn map_assistant(&mut self, message: AssistantMessage) -> Vec<ProviderEvent> {
        let mut events = Vec::new();
        let raw = message.raw.clone();
        if let Some(native) = message.session_id.as_deref() {
            self.set_native_thread(native);
        }
        let native_message_id = message.uuid.clone().filter(|id| !id.trim().is_empty());
        let parent_tool_use_id = message.parent_tool_use_id.clone();
        let suppress_text = self.take_streamed_text(message.message_id.as_deref());
        let suppress_thinking = self.take_streamed_thinking(message.message_id.as_deref());
        for block in message.content {
            match block {
                ContentBlock::Text(block) if !suppress_text => events.push(self.content_event(
                    StreamKind::AssistantText,
                    block.text,
                    self.raw("assistant", raw.clone()),
                    message.message_id.clone(),
                )),
                ContentBlock::Thinking(block) if !suppress_thinking => {
                    events.push(self.content_event(
                        StreamKind::ReasoningText,
                        block.thinking,
                        self.raw("assistant", raw.clone()),
                        message.message_id.clone(),
                    ))
                }
                ContentBlock::Text(_) | ContentBlock::Thinking(_) => {}
                ContentBlock::ToolUse(block) => {
                    let item_type = item_type_for_tool(&block.name);
                    self.open_items.insert(block.id.clone(), item_type.clone());
                    events.extend(self.item_started_updated(
                        block.id,
                        item_type,
                        block.name,
                        json!({ "type": "tool_use", "input": block.input }),
                        self.raw("assistant", raw.clone()),
                    ));
                }
                ContentBlock::ToolResult(block) => {
                    let item_type = self
                        .open_items
                        .remove(&block.tool_use_id)
                        .unwrap_or_else(|| "dynamic_tool_call".into());
                    events.extend(self.item_completed(
                        block.tool_use_id,
                        item_type,
                        "tool_result".into(),
                        json!({ "type": "tool_result", "content": block.content, "isError": block.is_error }),
                        self.raw("assistant", raw.clone()),
                        block.is_error.unwrap_or(false),
                    ));
                }
                ContentBlock::ServerToolUse(block) => {
                    let item_type = item_type_for_tool(&block.name);
                    self.open_items.insert(block.id.clone(), item_type.clone());
                    events.extend(self.item_started_updated(
                        block.id,
                        item_type,
                        block.name,
                        json!({ "type": "server_tool_use", "input": block.input }),
                        self.raw("assistant", raw.clone()),
                    ));
                }
                ContentBlock::ServerToolResult(block) => {
                    let item_type = self
                        .open_items
                        .remove(&block.tool_use_id)
                        .unwrap_or_else(|| "dynamic_tool_call".into());
                    events.extend(self.item_completed(
                        block.tool_use_id,
                        item_type,
                        "server_tool_result".into(),
                        json!({ "type": "server_tool_result", "content": block.content }),
                        self.raw("assistant", raw.clone()),
                        false,
                    ));
                }
                ContentBlock::Unknown(block) => events.push(self.event(
                    EventKind::ItemUpdated,
                    json!({
                        "itemType": "unknown",
                        "status": "inProgress",
                        "data": block.clone(),
                    }),
                    self.raw("assistant", raw.clone()),
                )),
            }
        }
        if events.is_empty() {
            events.push(self.event(
                EventKind::ItemUpdated,
                json!({ "itemType": "assistant_message", "status": "completed", "data": raw.clone() }),
                self.raw("assistant", raw),
            ));
        }
        for event in &mut events {
            if let Some(id) = &native_message_id {
                event.payload["nativeMessageId"] = json!(id);
            }
            if let Some(id) = &parent_tool_use_id {
                event.payload["parentToolUseId"] = json!(id);
                event.payload["nativeTask"] = json!(alera_provider_protocol::NativeTask {
                    native_tool_call_id: Some(id.clone()),
                    ..Default::default()
                });
            }
        }
        events
    }

    fn content_event(
        &self,
        stream_kind: StreamKind,
        delta: String,
        raw: RawEvent,
        item_id: Option<String>,
    ) -> ProviderEvent {
        let mut event = self.event(
            EventKind::ContentDelta,
            json!({ "streamKind": stream_kind, "delta": delta }),
            raw,
        );
        event.item_id = item_id;
        event.provider_refs = Some(alera_provider_protocol::ProviderRefs {
            provider_turn_id: None,
            provider_item_id: event.item_id.clone(),
            provider_request_id: None,
        });
        event
    }

    fn item_started_updated(
        &self,
        item_id: String,
        item_type: String,
        name: String,
        data: Value,
        raw: RawEvent,
    ) -> Vec<ProviderEvent> {
        let mut started = self.event(
            EventKind::ItemStarted,
            json!({
                "itemType": item_type.clone(),
                "status": "inProgress",
                "title": name.clone(),
                "data": data.clone(),
            }),
            raw.clone(),
        );
        started.item_id = Some(item_id.clone());
        started.provider_refs = Some(alera_provider_protocol::ProviderRefs {
            provider_turn_id: None,
            provider_item_id: started.item_id.clone(),
            provider_request_id: None,
        });
        let mut updated = self.event(
            EventKind::ItemUpdated,
            json!({
                "itemType": item_type,
                "status": "inProgress",
                "title": name,
                "data": data,
            }),
            raw,
        );
        updated.item_id = Some(item_id.clone());
        updated.provider_refs = Some(alera_provider_protocol::ProviderRefs {
            provider_turn_id: None,
            provider_item_id: updated.item_id.clone(),
            provider_request_id: None,
        });
        vec![started, updated]
    }

    fn item_completed(
        &self,
        item_id: String,
        item_type: String,
        title: String,
        data: Value,
        raw: RawEvent,
        failed: bool,
    ) -> Vec<ProviderEvent> {
        let mut completed = self.event(
            EventKind::ItemCompleted,
            json!({
                "itemType": item_type,
                "status": if failed { "failed" } else { "completed" },
                "title": title,
                "data": data,
            }),
            raw,
        );
        completed.item_id = Some(item_id);
        completed.provider_refs = Some(alera_provider_protocol::ProviderRefs {
            provider_turn_id: None,
            provider_item_id: completed.item_id.clone(),
            provider_request_id: None,
        });
        vec![completed]
    }

    pub(crate) fn map_stream(&mut self, message: StreamEvent) -> Vec<ProviderEvent> {
        let event = message.event.clone();
        let raw = self.raw("stream_event", message.raw);
        if event.get("type").and_then(Value::as_str) == Some("message_start") {
            self.stream_message_id = event
                .get("message")
                .and_then(|message| message.get("id"))
                .and_then(Value::as_str)
                .map(str::to_owned);
        }
        match event.get("type").and_then(Value::as_str) {
            Some("content_block_delta") => {
                let delta = event.get("delta").cloned().unwrap_or(Value::Null);
                let delta_type = delta
                    .get("type")
                    .and_then(Value::as_str)
                    .unwrap_or("unknown");
                let text = delta
                    .get("text")
                    .or_else(|| delta.get("thinking"))
                    .or_else(|| delta.get("partial_json"))
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_owned();
                let stream_kind = if delta_type.contains("thinking") {
                    StreamKind::ReasoningText
                } else if delta_type.contains("text") {
                    StreamKind::AssistantText
                } else {
                    StreamKind::Unknown
                };
                if !text.is_empty() && matches!(delta_type, "text_delta" | "thinking_delta") {
                    if delta_type == "text_delta" {
                        if let Some(message_id) = self.stream_message_id.clone() {
                            self.streamed_text_message_ids.insert(message_id);
                        } else {
                            self.streamed_text_unscoped = true;
                        }
                    } else if let Some(message_id) = self.stream_message_id.clone() {
                        self.streamed_thinking_message_ids.insert(message_id);
                    } else {
                        self.streamed_thinking_unscoped = true;
                    }
                }
                let item_id = event
                    .get("index")
                    .map(|index| index.to_string())
                    .and_then(|index| self.stream_items.get(&index).cloned());
                vec![self.content_event(stream_kind, text, raw.clone(), item_id)]
            }
            Some("content_block_start") => {
                let block = event.get("content_block").cloned().unwrap_or(Value::Null);
                let item_id = block
                    .get("id")
                    .and_then(Value::as_str)
                    .map(str::to_owned)
                    .or_else(|| event.get("index").map(|value| value.to_string()));
                let item_type = block
                    .get("name")
                    .and_then(Value::as_str)
                    .map(item_type_for_tool)
                    .unwrap_or_else(|| "unknown".into());
                let Some(item_id) = item_id else {
                    return vec![self.event(
                        EventKind::RuntimeWarning,
                        json!({ "message": "Claude content block had no item id", "detail": block }),
                        raw,
                    )];
                };
                if let Some(index) = event.get("index") {
                    self.stream_items.insert(index.to_string(), item_id.clone());
                }
                self.open_items.insert(item_id.clone(), item_type.clone());
                self.item_started_updated(
                    item_id,
                    item_type,
                    block
                        .get("name")
                        .and_then(Value::as_str)
                        .unwrap_or("content block")
                        .into(),
                    block,
                    raw,
                )
            }
            Some("content_block_stop") => {
                let Some(index) = event.get("index").map(Value::to_string) else {
                    return vec![self.event(
                        EventKind::RuntimeWarning,
                        json!({ "message": "Claude content block stop had no index", "detail": event }),
                        raw,
                    )];
                };
                let Some(item_id) = self.stream_items.remove(&index) else {
                    return vec![self.event(
                        EventKind::ItemUpdated,
                        json!({ "itemType": "unknown", "status": "completed", "data": event }),
                        raw,
                    )];
                };
                let item_type = self
                    .open_items
                    .remove(&item_id)
                    .unwrap_or_else(|| "unknown".into());
                self.item_completed(
                    item_id,
                    item_type,
                    "content block".into(),
                    event,
                    raw,
                    false,
                )
            }
            Some("message_stop") => {
                self.stream_message_id = None;
                vec![self.event(
                    EventKind::ItemUpdated,
                    json!({ "itemType": "assistant_message", "status": "completed", "data": event }),
                    raw,
                )]
            }
            _ => vec![self.event(
                EventKind::ItemUpdated,
                json!({ "itemType": "unknown", "status": "inProgress", "data": event }),
                raw,
            )],
        }
    }

    fn take_streamed_text(&mut self, message_id: Option<&str>) -> bool {
        let matched = message_id.is_some_and(|id| self.streamed_text_message_ids.remove(id));
        matched || std::mem::take(&mut self.streamed_text_unscoped)
    }

    fn take_streamed_thinking(&mut self, message_id: Option<&str>) -> bool {
        let matched = message_id.is_some_and(|id| self.streamed_thinking_message_ids.remove(id));
        matched || std::mem::take(&mut self.streamed_thinking_unscoped)
    }
}
