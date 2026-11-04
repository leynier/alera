//! `agentChat.generatedImage` (`agentChatGeneratedImagesV1`): one piece of
//! the image an `image_generation` item saved. Only the stored item names
//! the file; a client path is never read.

use alera_core::runtime::AgentChatStoreError;
use base64::Engine;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::commands::{optional_string, required_string};
use super::generated_image_files::{read_image_piece, ImageReadError, MAX_GENERATED_IMAGE_PIECE};
use super::AgentChatRuntime;

impl AgentChatRuntime {
    pub(crate) async fn generated_image(&self, request: &Value) -> HostResult<Value> {
        let chat_id = required_string(request, "chatId")?;
        let item_id = required_string(request, "itemId")?;
        let offset = integer(request, "offset", 0)?;
        let length = integer(request, "length", MAX_GENERATED_IMAGE_PIECE)?;
        if length == 0 || length > MAX_GENERATED_IMAGE_PIECE {
            return Err(HostError::format(format!(
                "length must be between 1 and {MAX_GENERATED_IMAGE_PIECE}"
            )));
        }
        if let Some(workspace_id) = optional_string(request, "workspaceId")? {
            let chat = self
                .store()
                .agent_chat(&chat_id)
                .await
                .map_err(|error| lookup_error(&chat_id, error))?
                .ok_or_else(|| conflict("chatNotFound", "Unknown chat."))?;
            if chat.workspace_id != workspace_id {
                return Err(HostError::format("workspaceId does not own the chat"));
            }
        }
        let item = self
            .store()
            .agent_chat_item_in_chat(&chat_id, &item_id)
            .await
            .map_err(|error| lookup_error(&chat_id, error))?;
        let path = generated_image_path(&item)?;
        let piece = tokio::task::spawn_blocking(move || {
            read_image_piece(std::path::Path::new(&path), offset, length)
        })
        .await
        .map_err(|error| HostError::state(error.to_string()))?
        .map_err(|error: ImageReadError| conflict(error.code(), error.message()))?;
        Ok(json!({
            "itemId": item_id,
            "mimeType": piece.mime_type,
            "sizeBytes": piece.size_bytes,
            "offset": piece.offset,
            "nextOffset": piece.next_offset,
            "contentToken": piece.content_token,
            "dataBase64": base64::engine::general_purpose::STANDARD.encode(piece.bytes),
        }))
    }
}

/// The saved path of a stored `image_generation` item.
pub(super) fn generated_image_path(item: &Value) -> HostResult<String> {
    if item["type"] != "image_generation" {
        return Err(conflict(
            "notGeneratedImage",
            "The item is not a generated image.",
        ));
    }
    item["normalized"]["imagePath"]
        .as_str()
        .or_else(|| item["data"]["savedPath"].as_str())
        .filter(|path| !path.trim().is_empty())
        .map(str::to_owned)
        .ok_or_else(|| {
            conflict(
                "generatedImageUnavailable",
                "The generated image has no saved file yet.",
            )
        })
}

fn integer(request: &Value, field: &str, default: u64) -> HostResult<u64> {
    match request.get(field) {
        None | Some(Value::Null) => Ok(default),
        Some(value) => value
            .as_u64()
            .ok_or_else(|| HostError::format(format!("{field} must be a nonnegative integer"))),
    }
}

fn conflict(code: &str, message: &str) -> HostError {
    HostError::conflict(code, message, json!({}))
}

fn lookup_error(chat_id: &str, error: anyhow::Error) -> HostError {
    match error.downcast_ref::<AgentChatStoreError>() {
        Some(AgentChatStoreError::NotFound(id)) if id == chat_id => {
            conflict("chatNotFound", "Unknown chat.")
        }
        Some(AgentChatStoreError::NotFound(_)) => conflict("itemNotFound", "Unknown item."),
        Some(AgentChatStoreError::Invalid(_)) => HostError::format(error.to_string()),
        _ => HostError::state(error.to_string()),
    }
}

#[cfg(test)]
#[path = "generated_image_reader_tests.rs"]
mod tests;
