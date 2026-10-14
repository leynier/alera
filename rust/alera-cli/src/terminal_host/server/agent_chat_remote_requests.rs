use super::{store_error, RemoteChatRouter, INTERNAL_CHAT_REQUEST};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::server::agent_chat_runtime::CallerCtx;
use crate::terminal_host::server::ServerActor;
use serde_json::{json, Value};

impl ServerActor {
    pub(in crate::terminal_host::server) fn remote_chat_router(&self) -> RemoteChatRouter {
        RemoteChatRouter::new(
            self.runtime_store.clone(),
            self.host_links.clone(),
            self.remote_agent_chats.clone(),
        )
    }

    pub(in crate::terminal_host::server) async fn try_start_agent_chat_remote_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        verb: &str,
        payload: &Value,
    ) -> HostResult<bool> {
        if !verb.starts_with("agentChat.") {
            return Ok(false);
        }
        self.require_auth(client_id)?;
        self.require_request_allowed(client_id, verb)?;
        if verb == INTERNAL_CHAT_REQUEST {
            if !self.is_hub_link_client(client_id) {
                return Err(HostError::conflict(
                    "chat_scope_denied",
                    "Only the registered hub link may drive an internal chat request.",
                    json!({}),
                ));
            }
            if payload["operation"] != "wire" {
                let runtime = self
                    .agent_chat_runtime()
                    .ok_or_else(|| HostError::state("Agent chats are unavailable."))?;
                let payload = payload.clone();
                self.spawn_deferred_request(client_id, request_id, async move {
                    crate::terminal_host::server::chat_orchestration_remote::handle_internal_runtime(&runtime, &payload)
                        .await
                });
                return Ok(true);
            }
            let caller: CallerCtx =
                crate::terminal_host::server::chat_orchestration_remote::decode(payload, "caller")?;
            let verb =
                crate::terminal_host::server::chat_orchestration_remote::text(payload, "verb")?;
            if verb == INTERNAL_CHAT_REQUEST || !verb.starts_with("agentChat.") {
                return Err(HostError::format("Invalid internal chat verb."));
            }
            let runtime = self
                .agent_chat_runtime()
                .ok_or_else(|| HostError::state("Agent chats are unavailable."))?;
            let request_payload = payload["payload"].clone();
            if self.start_provider_settings_request(
                client_id,
                request_id,
                &verb,
                &request_payload,
                caller.clone(),
            )? {
                return Ok(true);
            }
            let attachments = if verb == "agentChat.send" {
                let chat_id =
                    crate::terminal_host::server::agent_chat_runtime::commands::required_string(
                        &request_payload,
                        "chatId",
                    )?;
                Some(
                    self.validated_agent_chat_attachments(
                        client_id,
                        caller.mobile,
                        &chat_id,
                        &request_payload,
                    )
                    .await?,
                )
            } else {
                None
            };
            self.spawn_agent_chat_request(client_id, request_id, async move {
                crate::terminal_host::server::agent_chat_deferred::dispatch(
                    runtime,
                    &verb,
                    &request_payload,
                    caller,
                    attachments,
                )
                .await
            });
            return Ok(true);
        }
        // Mirrored satellite workspaces have local host ids and stay on their owner.
        let router = self.remote_chat_router();
        let workspace_id = match payload.get("chatId").and_then(Value::as_str) {
            Some(chat_id) => {
                if self
                    .runtime_store
                    .agent_chat(chat_id)
                    .await
                    .map_err(store_error)?
                    .is_some()
                {
                    return Ok(false);
                }
                router.directory.route(chat_id).map(|route| route.0)
            }
            None => payload
                .get("workspaceId")
                .and_then(Value::as_str)
                .map(str::to_owned),
        };
        let unscoped_list = verb == "agentChat.list" && workspace_id.is_none();
        let explicit_remote_host = payload
            .get("hostId")
            .and_then(Value::as_str)
            .is_some_and(|id| id != "local");
        if !unscoped_list
            && !explicit_remote_host
            && payload.get("chatId").is_none()
            && match &workspace_id {
                Some(id) => router.remote_workspace(id).await?.is_none(),
                None => true,
            }
        {
            return Ok(false);
        }
        let caller = self.agent_chat_caller(client_id);
        let payload = payload.clone();
        let verb = verb.to_owned();
        self.spawn_deferred_request(client_id, request_id, async move {
            router
                .forward_wire(&verb, &payload, caller)
                .await?
                .ok_or_else(|| HostError::conflict("chat_not_found", "Chat not found.", json!({})))
        });
        Ok(true)
    }
}
