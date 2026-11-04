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
            ChatRuntimeEvent::PreferencesChanged { revision } => {
                self.broadcast_agent_chat(event(
                    "agentChatPreferencesChanged",
                    json!({"revision":revision}),
                ));
            }
            ChatRuntimeEvent::Deleted {
                chat_id,
                workspace_id,
                discarded,
            } => {
                self.broadcast_agent_chat(event(
                    "agentChatDeleted",
                    json!({"chatId":chat_id,"workspaceId":workspace_id,"discarded":discarded}),
                ));
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

    #[tokio::test]
    async fn local_and_relayed_settings_events_require_negotiation_and_human_binding() {
        use crate::terminal_host::client::ClientHandle;
        use crate::terminal_host::server::actor_test_harness::{mobile_client, test_actor};
        use crate::terminal_host::server::chat_orchestration::BoundChat;
        use crate::terminal_host::server::{ClientState, ServerCommand};
        use std::collections::HashMap;
        use tokio::sync::mpsc;

        let dir = tempfile::tempdir().unwrap();
        let mut clients = HashMap::new();
        let mut receivers = Vec::new();
        for id in 0..6 {
            let (control, receiver) = mpsc::unbounded_channel();
            let (terminal, _terminal_receiver) = mpsc::channel(1);
            let handle = ClientHandle::new(control, terminal);
            let mut client = if id == 1 {
                mobile_client(handle, "fixture-phone")
            } else {
                ClientState::local(handle, true)
            };
            match id {
                2 => client.agent_chat_supported = false,
                3 => client.agent_chat_capability = false,
                4 => {
                    client.chat_orchestration_binding = Some(BoundChat {
                        chat_id: "fixture-chat".into(),
                        generation: 1,
                        runtime_mode: "approval-required".into(),
                        credential_hash: "fixture-hash".into(),
                        origin_host_id: None,
                    });
                }
                5 => client.authenticated = false,
                _ => {}
            }
            clients.insert(id, client);
            receivers.push(receiver);
        }
        let mut actor = test_actor(&dir, clients, HashMap::new()).await;
        actor.handle_agent_chat_runtime_event(super::ChatRuntimeEvent::PreferencesChanged {
            revision: 1,
        });
        actor
            .handle(ServerCommand::AgentChatSettingsChanged {
                name: "agentChatProvidersChanged".into(),
                payload: json!({"revision":2}),
            })
            .await;
        actor.relay_host_link_event(
            "fixture-host",
            "agentChatProvidersChanged",
            &json!({"revision":3}),
        );
        for (id, receiver) in receivers.iter_mut().enumerate() {
            let mut frames = Vec::new();
            while let Ok(frame) = receiver.try_recv() {
                frames.push(frame.as_json().unwrap());
            }
            if id < 2 {
                assert_eq!(frames.len(), 3);
                assert_eq!(frames[0]["payload"]["revision"], 1);
                assert_eq!(frames[1]["payload"]["revision"], 2);
                assert_eq!(frames[2]["payload"]["hostId"], "fixture-host");
            } else {
                assert!(
                    frames.is_empty(),
                    "restricted client {id} received settings"
                );
            }
        }
    }

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
