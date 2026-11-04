//! Codex `imageGeneration` items, as T3 Code: the root turn's completion
//! waits until every image it started has rendered, so a finished turn
//! never leaves an image behind it. Items are byte-free: the encoded image
//! stays in the adapter, and clients load the saved file.

use crate::provider::CodexProvider;
use crate::wire;
use alera_provider_protocol::{EventKind, ProviderEvent};
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};

#[derive(Debug, Default)]
pub(crate) struct ImageWork {
    /// Rendering image items by native root turn.
    running: HashMap<String, HashSet<String>>,
    /// A completion held until its turn's images render.
    held: Option<(String, ProviderEvent)>,
}

/// The canonical payload of an image generation item notification, or
/// None for any other item.
pub(crate) fn item_payload(method: &str, params: &Value) -> Option<Value> {
    let item = params
        .get("item")
        .filter(|item| item["type"] == "imageGeneration")?;
    let native_status = wire::string(item, "status");
    let failed = native_status.as_deref() == Some("failed")
        || item
            .get("failure")
            .is_some_and(|failure| !failure.is_null());
    let saved = wire::string(item, "savedPath").is_some_and(|path| !path.is_empty());
    let status = if failed {
        "failed"
    } else if native_status.as_deref() == Some("completed") || (method == "item/completed" && saved)
    {
        "completed"
    } else if method == "item/completed" {
        "failed"
    } else {
        "inProgress"
    };
    let mut data = item.clone();
    if let Some(data) = data.as_object_mut() {
        data.remove("result");
    }
    let mut payload = json!({
        "itemType": "image_generation",
        "status": status,
        "title": "Generated image",
        "data": data,
    });
    if let Some(prompt) = wire::string(item, "revisedPrompt").filter(|text| !text.trim().is_empty())
    {
        payload["detail"] = json!(prompt);
    }
    Some(payload)
}

impl<T> CodexProvider<T> {
    /// Holds a root turn's completion while its images render, and releases
    /// it after the last one.
    pub(crate) fn apply_image_notification(
        &mut self,
        method: &str,
        params: &Value,
        event: ProviderEvent,
    ) -> Option<ProviderEvent> {
        if self.root_thread(params).is_none() {
            return Some(event);
        }
        let Some(turn) =
            wire::string(params, "turnId").or_else(|| wire::nested_string(params, "turn", "id"))
        else {
            return Some(event);
        };
        let image = params
            .get("item")
            .filter(|item| item["type"] == "imageGeneration")
            .and_then(|item| wire::string(item, "id"));
        match (method, image) {
            ("item/started", Some(item)) => {
                self.images.running.entry(turn).or_default().insert(item);
                Some(event)
            }
            ("item/completed", Some(item)) => {
                let running = self.images.running.get_mut(&turn);
                let drained = running.is_some_and(|items| items.remove(&item) && items.is_empty());
                if !drained {
                    return Some(event);
                }
                self.images.running.remove(&turn);
                match self.images.held.take() {
                    Some((held_turn, completion)) if held_turn == turn => {
                        self.queued_events.push_back(event);
                        self.queued_events.push_back(completion);
                        None
                    }
                    other => {
                        self.images.held = other;
                        Some(event)
                    }
                }
            }
            ("turn/completed", _) => {
                let rendering = self
                    .images
                    .running
                    .get(&turn)
                    .is_some_and(|items| !items.is_empty());
                if rendering
                    && event.kind == EventKind::TurnCompleted
                    && event.payload["state"] == "completed"
                {
                    self.images.held = Some((turn, event));
                    return None;
                }
                self.images.running.remove(&turn);
                Some(event)
            }
            ("turn/aborted", _) => {
                self.images.running.remove(&turn);
                Some(event)
            }
            _ => Some(event),
        }
    }

    /// Delivers a held completion now, when a stop or the stream's end
    /// cannot wait for the images. Returns whether one was held.
    pub(crate) fn release_image_hold(&mut self) -> bool {
        self.images.running.clear();
        let Some((_, completion)) = self.images.held.take() else {
            return false;
        };
        self.queued_events.push_back(completion);
        true
    }

    pub(crate) fn image_hold_active(&self) -> bool {
        self.images.held.is_some()
    }
}
