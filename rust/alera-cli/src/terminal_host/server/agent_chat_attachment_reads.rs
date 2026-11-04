//! `agentChat.attachment.read`: the host side of attachment thumbnails. The
//! caller is authorized as for `agentChat.snapshot`; the store then checks
//! that the attachment was uploaded to that chat. A hub forwards the verb
//! for a satellite's chat only when the satellite advertises the capability.

use serde_json::{json, Value};

use super::agent_chat_attachment_store::{AttachmentRead, ChatAttachmentStore, READ_PIECE_BYTES};
use super::agent_chat_runtime::commands::{optional_string, required_string};
use super::agent_chat_runtime::CallerCtx;
use super::ServerActor;
use crate::terminal_host::host_error::{HostError, HostResult};

pub(super) const READ_VERB: &str = "agentChat.attachment.read";
pub(super) const READ_CAPABILITY: &str = "agentChatAttachmentReadV1";

pub(super) fn require_remote_read_capability(
    payload: &Value,
    capabilities: &[String],
) -> HostResult<()> {
    if payload["operation"] == "wire"
        && payload["verb"] == READ_VERB
        && !capabilities
            .iter()
            .any(|capability| capability == READ_CAPABILITY)
    {
        return Err(HostError::conflict(
            "unsupported",
            "Update the remote runtime to preview chat attachments.",
            json!({"capability": READ_CAPABILITY}),
        ));
    }
    Ok(())
}

fn integer(payload: &Value, field: &str, default: u64) -> HostResult<u64> {
    match payload.get(field) {
        None | Some(Value::Null) => Ok(default),
        Some(value) => value
            .as_u64()
            .ok_or_else(|| HostError::format(format!("{field} must be a nonnegative integer"))),
    }
}

impl ServerActor {
    pub(super) async fn chat_attachment_read_task(
        &self,
        payload: &Value,
        caller: &CallerCtx,
    ) -> HostResult<impl std::future::Future<Output = HostResult<Value>> + Send + 'static> {
        let chat_id = required_string(payload, "chatId")?;
        let attachment_id = required_string(payload, "attachmentId")?;
        let offset = integer(payload, "offset", 0)?;
        let length = integer(payload, "length", READ_PIECE_BYTES)?;
        let chat = self
            .runtime_store
            .agent_chat(&chat_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::conflict("chat_not_found", "Chat not found.", json!({})))?;
        if optional_string(payload, "workspaceId")?
            .is_some_and(|workspace_id| workspace_id != chat.workspace_id)
        {
            return Err(HostError::conflict(
                "attachment_scope_denied",
                "The attachment workspace does not own this chat.",
                json!({}),
            ));
        }
        let runtime_dir = self.runtime_dir.clone();
        let caller = caller.scope.clone();
        Ok(async move {
            tokio::task::spawn_blocking(move || {
                ChatAttachmentStore::in_runtime_dir(&runtime_dir).locked(|store| {
                    store.read_piece(&AttachmentRead {
                        workspace_id: &chat.workspace_id,
                        chat_id: &chat_id,
                        caller: &caller,
                        attachment_id: &attachment_id,
                        offset,
                        length,
                    })
                })
            })
            .await
            .map_err(|error| HostError::state(error.to_string()))?
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_satellite_without_the_capability_is_never_asked_to_read() {
        let payload = json!({"operation":"wire", "verb": READ_VERB});
        let error = require_remote_read_capability(&payload, &[]).unwrap_err();
        assert!(matches!(error, HostError::Conflict { ref code, .. } if code == "unsupported"));
        assert!(require_remote_read_capability(&payload, &[READ_CAPABILITY.into()]).is_ok());
        // Uploads keep their own capability; reads do not need it.
        assert!(require_remote_read_capability(
            &payload,
            &["agentChatAttachmentUploadV1".into(), READ_CAPABILITY.into()]
        )
        .is_ok());
        assert!(
            super::super::agent_chat_attachment_requests::require_remote_upload_capability(
                &payload,
                &[READ_CAPABILITY.into()]
            )
            .is_ok()
        );
        assert!(require_remote_read_capability(
            &json!({"operation":"wire", "verb":"agentChat.snapshot"}),
            &[]
        )
        .is_ok());
    }

    #[tokio::test]
    async fn a_remote_chat_attachment_read_routes_to_its_owner_with_the_caller() {
        let (_root, router, host) = super::super::agent_chat_remote::tests::remote_fixture().await;
        let caller = CallerCtx {
            scope: "mobile:phone".into(),
            actor: "mobile:phone".into(),
            mobile: true,
        };
        let payload = json!({"workspaceId":"task", "chatId":"remote-chat", "attachmentId":"26ff2908-0cbd-4c5b-ad34-a8900ee80204", "offset":0, "length":262144});
        router
            .forward_wire(READ_VERB, &payload, caller.clone())
            .await
            .unwrap();
        let calls = host.calls.lock().unwrap();
        let (workspace_id, verb, envelope) = calls
            .iter()
            .find(|(_, _, envelope)| envelope["verb"] == READ_VERB)
            .unwrap();
        assert_eq!(workspace_id, "task");
        assert_eq!(verb, super::super::agent_chat_remote::INTERNAL_CHAT_REQUEST);
        assert_eq!(envelope["caller"], json!(caller));
        assert_eq!(envelope["payload"], payload);
    }

    #[test]
    fn paired_phones_may_read_attachments() {
        assert!(super::super::mobile_gateway_surface::mobile_request_allowed(READ_VERB));
        assert!(
            super::super::mobile_gateway_surface::MOBILE_HELLO_CAPABILITIES
                .contains(&READ_CAPABILITY)
        );
        assert!(
            crate::terminal_host::agent_chat_capabilities::AGENT_CHAT_EXPERIENCE_CAPABILITIES
                .contains(&READ_CAPABILITY)
        );
    }
}
