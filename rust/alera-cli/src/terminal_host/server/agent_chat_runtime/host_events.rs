use std::collections::BTreeSet;

use serde_json::json;

use crate::terminal_host::protocol::event;
use crate::terminal_host::server::ServerActor;

use super::events::ChatRuntimeEvent;

impl ServerActor {
    pub(crate) fn handle_agent_chat_runtime_event(&self, runtime_event: ChatRuntimeEvent) {
        match runtime_event {
            ChatRuntimeEvent::Changed {
                chat_id,
                workspace_id,
                cursor,
                delta,
            } => self.broadcast_agent_chat(event(
                "agentChatChanged",
                json!({
                    "chatId": chat_id,
                    "workspaceId": workspace_id,
                    "cursor": cursor,
                    "delta": public_chat_delta(delta),
                }),
            )),
            ChatRuntimeEvent::ChatsChanged { workspace_id } => self.broadcast_agent_chat(event(
                "agentChatsChanged",
                json!({ "workspaceId": workspace_id }),
            )),
            ChatRuntimeEvent::TabsChanged { workspace_id } => {
                self.broadcast_workspace_tabs_changed(Some(&workspace_id));
            }
        }
    }
}

fn public_chat_delta(mut delta: serde_json::Value) -> serde_json::Value {
    let Some(object) = delta.as_object_mut() else {
        return delta;
    };
    let hidden_ids: BTreeSet<String> = object
        .get("items")
        .and_then(serde_json::Value::as_array)
        .into_iter()
        .flatten()
        .filter(|item| item["type"] == "payload" && item["normalized"]["hidden"] == true)
        .filter_map(|item| item["itemId"].as_str().map(str::to_owned))
        .collect();
    let remove_items = object
        .get_mut("items")
        .and_then(serde_json::Value::as_array_mut)
        .map(|items| {
            items.retain(|item| {
                !(item["type"] == "payload" && item["normalized"]["hidden"] == true)
            });
            items.is_empty()
        })
        .unwrap_or(false);
    if remove_items {
        object.remove("items");
    }
    let remove_appends = object
        .get_mut("textAppends")
        .and_then(serde_json::Value::as_array_mut)
        .map(|appends| {
            appends.retain(|append| {
                append["itemId"]
                    .as_str()
                    .is_none_or(|id| !hidden_ids.contains(id))
            });
            appends.is_empty()
        })
        .unwrap_or(false);
    if remove_appends {
        object.remove("textAppends");
    }
    delta
}

#[cfg(test)]
mod tests {
    use super::public_chat_delta;
    use serde_json::json;

    #[test]
    fn hidden_payload_rows_are_removed_from_public_delta() {
        let delta = public_chat_delta(json!({
            "items": [
                {"itemId":"visible", "type":"assistant_message"},
                {"itemId":"head:payload:1", "type":"payload", "normalized":{"hidden":true}}
            ],
            "removedItemIds": ["visible", "head:payload:2"],
            "textAppends": [{"itemId":"head:payload:1", "text":"retained native data"}]
        }));
        assert_eq!(delta["items"].as_array().unwrap().len(), 1);
        assert_eq!(
            delta["removedItemIds"],
            json!(["visible", "head:payload:2"])
        );
        assert!(delta.get("textAppends").is_none());
    }

    #[test]
    fn hidden_only_delta_is_empty() {
        let delta = public_chat_delta(json!({
            "items": [{"itemId":"head:payload:1", "type":"payload", "normalized":{"hidden":true}}]
        }));
        assert_eq!(delta, json!({}));
    }

    #[test]
    fn visible_future_items_keep_their_data_appends_and_removals_regardless_of_id() {
        let expected = json!({
            "items": [{
                "itemId":"native:payload:visible", "type":"future_item",
                "normalized":{"hidden":true, "futureAttribute":{"retained":true}},
                "data":{"complete":"future native data"}
            }],
            "textAppends":[{"itemId":"native:payload:visible", "text":"visible text"}],
            "removedItemIds":["native:payload:visible", "unknown:payload:identifier"]
        });
        assert_eq!(public_chat_delta(expected.clone()), expected);
    }
}
