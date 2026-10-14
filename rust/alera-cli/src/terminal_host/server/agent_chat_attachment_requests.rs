use std::collections::HashSet;

use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;
use serde_json::{json, Value};

use super::agent_chat_attachment_store::{
    AttachmentScope, AttachmentUploadSpec, ChatAttachmentStore, CHUNK_BYTES,
};
use super::agent_chat_runtime::{commands::required_string, CallerCtx};
use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) fn handles(verb: &str) -> bool {
    matches!(
        verb,
        "agentChat.attachment.start"
            | "agentChat.attachment.chunk"
            | "agentChat.attachment.complete"
            | "agentChat.attachment.cancel"
    )
}

pub(super) fn require_remote_upload_capability(
    payload: &Value,
    capabilities: &[String],
) -> HostResult<()> {
    if payload["operation"] == "wire"
        && payload["verb"].as_str().is_some_and(handles)
        && !capabilities
            .iter()
            .any(|capability| capability == "agentChatAttachmentUploadV1")
    {
        return Err(HostError::conflict(
            "unsupported",
            "Update the remote runtime to upload chat attachments.",
            json!({"capability": "agentChatAttachmentUploadV1"}),
        ));
    }
    Ok(())
}

impl ServerActor {
    pub(super) async fn try_start_chat_attachment_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        verb: &str,
        payload: &Value,
        caller: CallerCtx,
    ) -> HostResult<bool> {
        if !handles(verb) {
            return Ok(false);
        }
        let task = self
            .chat_attachment_request_task(client_id, verb, payload, &caller)
            .await?;
        self.spawn_agent_chat_request(client_id, request_id, task);
        Ok(true)
    }

    async fn chat_attachment_request_task(
        &self,
        client_id: u64,
        verb: &str,
        payload: &Value,
        caller: &CallerCtx,
    ) -> HostResult<impl std::future::Future<Output = HostResult<Value>> + Send + 'static> {
        require_human(caller)?;
        if self.chat_orchestration_binding(client_id).is_some() {
            return Err(HostError::conflict(
                "attachment_scope_denied",
                "Agent credentials cannot upload human chat attachments.",
                json!({}),
            ));
        }
        if payload
            .get("dataBase64")
            .and_then(Value::as_str)
            .is_some_and(|encoded| encoded.len() > CHUNK_BYTES.div_ceil(3) * 4)
            || payload
                .get("name")
                .and_then(Value::as_str)
                .is_some_and(|name| name.len() > 180)
        {
            return Err(HostError::format(
                "Chat attachment upload exceeds its request budget.",
            ));
        }
        let chat_id = required_string(payload, "chatId")?;
        let workspace_id = required_string(payload, "workspaceId")?;
        let chat = self
            .runtime_store
            .agent_chat(&chat_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::conflict("chat_not_found", "Chat not found.", json!({})))?;
        if chat.workspace_id != workspace_id {
            return Err(HostError::conflict(
                "attachment_scope_denied",
                "The attachment workspace does not own this chat.",
                json!({}),
            ));
        }
        self.runtime_store
            .find_workspace(&workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| {
                HostError::conflict(
                    "workspace_not_found",
                    "The chat workspace no longer exists.",
                    json!({}),
                )
            })?;
        let scope = AttachmentScope {
            caller: caller.scope.clone(),
            workspace_id,
            chat_id,
        };
        let live_chats = if verb == "agentChat.attachment.start" {
            self.runtime_store
                .list_all_agent_chats(true)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
                .into_iter()
                .map(|chat| chat.chat_id)
                .collect::<HashSet<_>>()
        } else {
            HashSet::new()
        };
        let runtime_dir = self.runtime_dir.clone();
        let verb = verb.to_owned();
        let payload = payload.clone();
        Ok(async move {
            tokio::task::spawn_blocking(move || {
                let store = ChatAttachmentStore::in_runtime_dir(&runtime_dir);
                store.locked(|store| dispatch(store, &scope, &verb, &payload, &live_chats))
            })
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        })
    }

    pub(super) async fn handle_chat_attachment_request(
        &self,
        client_id: u64,
        verb: &str,
        payload: &Value,
        caller: &CallerCtx,
    ) -> HostResult<Value> {
        self.chat_attachment_request_task(client_id, verb, payload, caller)
            .await?
            .await
    }

    pub(super) async fn resolve_chat_upload(
        &self,
        caller: &CallerCtx,
        workspace_id: &str,
        chat_id: &str,
        attachment_id: &str,
    ) -> HostResult<Value> {
        require_human(caller)?;
        let scope = AttachmentScope {
            caller: caller.scope.clone(),
            workspace_id: workspace_id.into(),
            chat_id: chat_id.into(),
        };
        let runtime_dir = self.runtime_dir.clone();
        let attachment_id = attachment_id.to_owned();
        tokio::task::spawn_blocking(move || {
            let store = ChatAttachmentStore::in_runtime_dir(&runtime_dir);
            store.locked(|store| store.resolve(&scope, &attachment_id))
        })
        .await
        .map_err(|error| HostError::state(error.to_string()))?
    }
}

fn require_human(caller: &CallerCtx) -> HostResult<()> {
    if caller.actor != caller.scope
        || (!matches!(caller.scope.as_str(), "desktop" | "cli")
            && !(caller.mobile
                && caller.scope.starts_with("mobile:")
                && caller.scope != "mobile:unknown"))
    {
        return Err(HostError::conflict(
            "attachment_scope_denied",
            "Only an authenticated person may upload chat attachments.",
            json!({}),
        ));
    }
    Ok(())
}

fn dispatch(
    store: &ChatAttachmentStore,
    scope: &AttachmentScope,
    verb: &str,
    payload: &Value,
    live_chats: &HashSet<String>,
) -> HostResult<Value> {
    let upload_id = required_string(payload, "uploadId")?;
    match verb {
        "agentChat.attachment.start" => store.start(
            scope,
            &upload_id,
            &AttachmentUploadSpec {
                name: &required_string(payload, "name")?,
                attachment_type: &required_string(payload, "type")?,
                size_bytes: payload["sizeBytes"].as_u64().ok_or_else(|| {
                    HostError::format("Chat attachment sizeBytes must be an integer.")
                })?,
                source_digest: payload.get("sourceDigest").and_then(Value::as_str),
            },
            live_chats,
        ),
        "agentChat.attachment.chunk" => {
            let offset = payload["offset"]
                .as_u64()
                .ok_or_else(|| HostError::format("Chat attachment offset must be an integer."))?;
            let encoded = required_string(payload, "dataBase64")?;
            if encoded.len() > CHUNK_BYTES.div_ceil(3) * 4 {
                return Err(HostError::format("Chat attachment chunk is too large."));
            }
            let bytes = STANDARD
                .decode(encoded.as_bytes())
                .map_err(|_| HostError::format("Chat attachment chunk is not valid base64."))?;
            Ok(json!({"nextOffset": store.append(scope, &upload_id, offset, &bytes)?}))
        }
        "agentChat.attachment.complete" => store.complete(scope, &upload_id),
        "agentChat.attachment.cancel" => {
            store.cancel(scope, &upload_id)?;
            Ok(json!({}))
        }
        _ => Err(HostError::format("Unknown chat attachment operation.")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_authenticated_human_scopes_can_upload() {
        assert!(require_human(&CallerCtx::runtime()).is_err());
        for scope in ["agent:worker", "mcp:client", "mobile:unknown"] {
            assert!(require_human(&CallerCtx {
                scope: scope.into(),
                actor: scope.into(),
                mobile: true
            })
            .is_err());
        }
        for scope in ["desktop", "cli", "mobile:phone"] {
            assert!(require_human(&CallerCtx {
                scope: scope.into(),
                actor: scope.into(),
                mobile: scope.starts_with("mobile:")
            })
            .is_ok());
        }
    }

    #[test]
    fn owner_upload_capability_is_required_even_when_the_hub_is_new() {
        let payload = json!({"operation":"wire", "verb":"agentChat.attachment.start"});
        assert!(require_remote_upload_capability(&payload, &[]).is_err());
        assert!(require_remote_upload_capability(
            &payload,
            &["agentChatAttachmentUploadV1".into()]
        )
        .is_ok());
        assert!(require_remote_upload_capability(
            &json!({"operation":"wire", "verb":"agentChat.send"}),
            &[]
        )
        .is_ok());
    }

    #[tokio::test]
    async fn paired_phone_upload_routes_to_chat_owner_with_original_human_identity() {
        let (_root, router, host) = super::super::agent_chat_remote::tests::remote_fixture().await;
        let caller = CallerCtx {
            scope: "mobile:phone".into(),
            actor: "mobile:phone".into(),
            mobile: true,
        };
        let payload = json!({"workspaceId":"task", "chatId":"remote-chat", "uploadId":"26ff2908-0cbd-4c5b-ad34-a8900ee80204", "name":"report.md", "type":"file", "sizeBytes":5});
        router
            .forward_wire("agentChat.attachment.start", &payload, caller.clone())
            .await
            .unwrap();
        let calls = host.calls.lock().unwrap();
        let (workspace_id, verb, envelope) = calls
            .iter()
            .find(|(_, _, envelope)| envelope["verb"] == "agentChat.attachment.start")
            .unwrap();
        assert_eq!(workspace_id, "task");
        assert_eq!(verb, super::super::agent_chat_remote::INTERNAL_CHAT_REQUEST);
        assert_eq!(envelope["caller"], json!(caller));
        assert_eq!(envelope["payload"], payload);
        assert!(envelope["payload"].get("path").is_none());
    }
}
