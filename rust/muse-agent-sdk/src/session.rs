use serde_json::Value;
use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq)]
pub struct ItemState {
    pub item_id: String,
    pub revision: u64,
    pub status: String,
    pub kind: String,
    pub turn_id: Option<String>,
    pub value: Value,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PendingApproval {
    pub approval_id: String,
    pub turn_id: Option<String>,
    pub item_id: Option<String>,
    pub tool_call_id: Option<String>,
    pub tool_name: Option<String>,
    pub choices: Vec<Value>,
    pub requirement_id: Option<Value>,
    pub value: Value,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PendingUserInput {
    pub user_input_id: String,
    pub turn_id: Option<String>,
    pub item_id: Option<String>,
    pub tool_call_id: Option<String>,
    pub tool_name: Option<String>,
    pub questions: Vec<Value>,
    pub value: Value,
}

/// Client-side fold of the versioned MSP view stream.
///
/// The host remains authoritative. The fold only replaces an item when its
/// revision increases, keeps opaque cursors verbatim, and records gaps so an
/// adapter can re-anchor or page instead of pretending a dropped event was
/// delivered.
#[derive(Debug, Clone, Default)]
pub struct SessionState {
    pub session_id: Option<String>,
    pub cursor: Option<String>,
    pub active_turn_id: Option<String>,
    pub items: HashMap<String, ItemState>,
    pub approvals: HashMap<String, PendingApproval>,
    pub user_inputs: HashMap<String, PendingUserInput>,
    pub gap: Option<(String, String)>,
    pub raw_events: Vec<Value>,
}

impl SessionState {
    /// Fold a session/start or session/resume result before live notifications arrive.
    pub fn apply_snapshot(&mut self, result: &Value) {
        self.raw_events
            .push(serde_json::json!({"snapshot": result}));
        if let Some(session) = result.get("session") {
            self.session_id = string(session, "sessionId").or(self.session_id.take());
            self.active_turn_id = string(session, "activeTurnId");
        }
        if let Some(cursor) = result.get("viewCursor").and_then(Value::as_str) {
            self.cursor = Some(cursor.into());
        }
        let history = result.get("history");
        let state = history
            .and_then(|history| history.get("snapshot"))
            .and_then(|snapshot| snapshot.get("state"));
        if let Some(items) = state
            .and_then(|state| state.get("items"))
            .and_then(Value::as_array)
            .or_else(|| {
                history
                    .and_then(|history| history.get("items"))
                    .and_then(Value::as_array)
            })
        {
            for item in items {
                self.apply_item(item);
            }
        }
        if let Some(snapshot_cursor) = history
            .and_then(|history| history.get("snapshot"))
            .and_then(|snapshot| snapshot.get("viewCursor"))
            .and_then(Value::as_str)
        {
            self.cursor = Some(snapshot_cursor.into());
        }
        self.gap = None;
    }

    /// Fold a paged view response while preserving the server's opaque cursor.
    pub fn apply_page(&mut self, result: &Value) {
        if let Some(events) = result.get("events").and_then(Value::as_array) {
            for event in events {
                if let (Some(method), Some(params)) = (
                    event.get("method").and_then(Value::as_str),
                    event.get("params"),
                ) {
                    self.apply(method, params);
                }
            }
        }
        if let Some(cursor) = result.get("nextCursor").and_then(Value::as_str) {
            self.cursor = Some(cursor.into());
        }
    }

    pub fn apply(&mut self, method: &str, params: &Value) {
        self.raw_events
            .push(serde_json::json!({"method": method, "params": params}));
        if let Some(session_id) = params.get("sessionId").and_then(Value::as_str) {
            self.session_id = Some(session_id.into());
        }
        if let Some(cursor) = params.get("viewCursor").and_then(Value::as_str) {
            self.cursor = Some(cursor.into());
        }
        match method {
            "session/started" => {
                if let Some(session) = params.get("session") {
                    self.session_id = string(session, "sessionId").or(self.session_id.take());
                    self.active_turn_id = string(session, "activeTurnId");
                }
            }
            "view/gap" => {
                if let (Some(after), Some(next)) = (
                    params.get("after").and_then(Value::as_str),
                    params.get("next").and_then(Value::as_str),
                ) {
                    self.gap = Some((after.into(), next.into()));
                }
            }
            "turn/started" => {
                self.active_turn_id = params
                    .get("turnId")
                    .and_then(Value::as_str)
                    .map(str::to_owned);
            }
            "turn/completed" | "turn/cancelled" => {
                let turn = params.get("turnId").and_then(Value::as_str);
                if turn.is_some() && self.active_turn_id.as_deref() == turn {
                    self.active_turn_id = None;
                }
            }
            "item/started" | "item/updated" | "item/completed" => {
                if let Some(item) = params.get("item") {
                    self.apply_item(item);
                }
            }
            "approval/request" | "approval/requested" => {
                if let Some(id) = params.get("approvalId").and_then(Value::as_str) {
                    self.approvals.insert(
                        id.into(),
                        PendingApproval {
                            approval_id: id.into(),
                            turn_id: string(params, "turnId"),
                            item_id: string(params, "itemId"),
                            tool_call_id: string(params, "toolCallId"),
                            tool_name: string(params, "toolName"),
                            choices: params
                                .get("availableChoices")
                                .and_then(Value::as_array)
                                .cloned()
                                .unwrap_or_default(),
                            requirement_id: params.get("currentRequirementId").cloned(),
                            value: params.clone(),
                        },
                    );
                }
            }
            "approval/resolved" | "approval/updated" => {
                if let Some(id) = params.get("approvalId").and_then(Value::as_str) {
                    self.approvals.remove(id);
                }
            }
            "userInput/request" | "userInput/requested" => {
                if let Some(id) = params.get("userInputId").and_then(Value::as_str) {
                    self.user_inputs.insert(
                        id.into(),
                        PendingUserInput {
                            user_input_id: id.into(),
                            turn_id: string(params, "turnId"),
                            item_id: string(params, "itemId"),
                            tool_call_id: string(params, "toolCallId"),
                            tool_name: string(params, "toolName"),
                            questions: params
                                .get("questions")
                                .and_then(Value::as_array)
                                .cloned()
                                .unwrap_or_default(),
                            value: params.clone(),
                        },
                    );
                }
            }
            "userInput/settled" | "userInput/cancelled" => {
                if let Some(id) = params.get("userInputId").and_then(Value::as_str) {
                    self.user_inputs.remove(id);
                }
            }
            _ => {}
        }
    }

    fn apply_item(&mut self, item: &Value) {
        let Some(item_id) = item.get("itemId").and_then(Value::as_str) else {
            return;
        };
        let revision = item.get("revision").and_then(Value::as_u64).unwrap_or(0);
        if self
            .items
            .get(item_id)
            .is_some_and(|previous| previous.revision >= revision)
        {
            return;
        }
        self.items.insert(
            item_id.into(),
            ItemState {
                item_id: item_id.into(),
                revision,
                status: item
                    .get("status")
                    .and_then(Value::as_str)
                    .unwrap_or("unknown")
                    .into(),
                kind: item
                    .get("kind")
                    .and_then(Value::as_str)
                    .unwrap_or("unknown")
                    .into(),
                turn_id: item
                    .get("turnId")
                    .and_then(Value::as_str)
                    .map(str::to_owned),
                value: item.clone(),
            },
        );
    }

    pub fn snapshot(&self) -> Value {
        let items = self
            .items
            .values()
            .map(|item| item.value.clone())
            .collect::<Vec<_>>();
        serde_json::json!({
            "sessionId": self.session_id,
            "viewCursor": self.cursor,
            "activeTurnId": self.active_turn_id,
            "items": items,
            "pendingApprovals": self.approvals.values().map(|item| item.value.clone()).collect::<Vec<_>>(),
            "pendingUserInputs": self.user_inputs.values().map(|item| item.value.clone()).collect::<Vec<_>>(),
            "gap": self.gap.as_ref().map(|(after, next)| serde_json::json!({"after": after, "next": next})),
        })
    }
}

fn string(params: &Value, key: &str) -> Option<String> {
    params.get(key).and_then(Value::as_str).map(str::to_owned)
}
