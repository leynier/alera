use serde_json::{json, Value};
use std::path::{Path, PathBuf};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::agent_chat_runtime::commands::{required_string, CallerCtx};
use super::agent_chat_runtime::AgentChatRuntime;
use super::{ClientKind, ServerActor};

impl ServerActor {
    pub(super) async fn try_start_local_agent_chat_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<bool> {
        if !request_type.starts_with("agentChat.") {
            return Ok(false);
        }
        self.require_auth(client_id)?;
        self.require_request_allowed(client_id, request_type)?;
        let ctx = self.agent_chat_caller(client_id);
        if self
            .try_start_chat_attachment_request(
                client_id,
                request_id,
                request_type,
                payload,
                ctx.clone(),
            )
            .await?
        {
            return Ok(true);
        }
        if super::agent_chat_provider_settings::ProviderSettingsService::handles(request_type) {
            let service = self.agent_chat_provider_settings.clone().ok_or_else(|| {
                HostError::conflict(
                    "unsupported",
                    "Provider settings are unavailable.",
                    json!({}),
                )
            })?;
            let ctx = self.agent_chat_caller(client_id);
            let verb = request_type.to_owned();
            let payload = payload.clone();
            self.spawn_agent_chat_request(client_id, request_id, async move {
                service.dispatch(&verb, &payload, &ctx).await
            });
            return Ok(true);
        }
        let runtime = self.agent_chat_runtime().ok_or_else(|| {
            HostError::conflict("unsupported", "Agent chats are unavailable.", json!({}))
        })?;
        let ctx = self.agent_chat_caller(client_id);
        let attachments = if request_type == "agentChat.send" {
            let chat_id = required_string(payload, "chatId")?;
            Some(
                self.validated_agent_chat_attachments(client_id, &ctx, &chat_id, payload)
                    .await?,
            )
        } else {
            None
        };
        let request_type = request_type.to_owned();
        let payload = payload.clone();
        self.spawn_agent_chat_request(client_id, request_id, async move {
            super::agent_chat_deferred::dispatch(runtime, &request_type, &payload, ctx, attachments)
                .await
        });
        Ok(true)
    }

    pub(super) fn spawn_agent_chat_request<F>(&self, client_id: u64, request_id: i64, task: F)
    where
        F: std::future::Future<Output = HostResult<Value>> + Send + 'static,
    {
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = task.await;
            let _ = inbox
                .send_wait(super::ServerCommand::AgentChatRequestFinished {
                    client_id,
                    request_id,
                    result,
                })
                .await;
        });
    }

    pub(super) fn agent_chat_runtime(&self) -> Option<AgentChatRuntime> {
        self.agent_chat_runtime.clone()
    }

    pub(super) async fn handle_agent_chat_request(
        &mut self,
        client_id: u64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<Value> {
        let ctx = self.agent_chat_caller(client_id);
        self.handle_agent_chat_request_with_caller(client_id, request_type, payload, ctx)
            .await
    }

    pub(crate) async fn handle_agent_chat_request_with_caller(
        &mut self,
        client_id: u64,
        request_type: &str,
        payload: &Value,
        ctx: CallerCtx,
    ) -> HostResult<Value> {
        if super::agent_chat_attachment_requests::handles(request_type) {
            return self
                .handle_chat_attachment_request(client_id, request_type, payload, &ctx)
                .await;
        }
        if super::agent_chat_provider_settings::ProviderSettingsService::handles(request_type) {
            return self
                .agent_chat_provider_settings
                .as_ref()
                .ok_or_else(|| {
                    HostError::conflict(
                        "unsupported",
                        "Provider settings are unavailable.",
                        json!({}),
                    )
                })?
                .dispatch(request_type, payload, &ctx)
                .await;
        }
        let runtime = self.agent_chat_runtime().ok_or_else(|| {
            HostError::conflict("unsupported", "Agent chats are unavailable.", json!({}))
        })?;
        let attachments = if request_type == "agentChat.send" {
            let chat_id = required_string(payload, "chatId")?;
            Some(
                self.validated_agent_chat_attachments(client_id, &ctx, &chat_id, payload)
                    .await?,
            )
        } else {
            None
        };
        super::agent_chat_deferred::dispatch(runtime, request_type, payload, ctx, attachments).await
    }

    pub(super) fn agent_chat_caller(&self, client_id: u64) -> CallerCtx {
        let Some(client) = self.clients.get(&client_id) else {
            return CallerCtx::runtime();
        };
        if client.kind == ClientKind::Mobile {
            let device = client
                .mobile_device_id
                .as_deref()
                .unwrap_or("unknown")
                .to_string();
            CallerCtx {
                scope: format!("mobile:{device}"),
                actor: format!("mobile:{device}"),
                mobile: true,
            }
        } else {
            let scope = match client.local_role {
                super::client_delivery::LocalClientRole::App => "desktop",
                super::client_delivery::LocalClientRole::Cli => "cli",
            };
            CallerCtx {
                scope: scope.into(),
                actor: scope.into(),
                mobile: false,
            }
        }
    }
}

impl ServerActor {
    pub(super) async fn validated_agent_chat_attachments(
        &self,
        client_id: u64,
        caller: &CallerCtx,
        chat_id: &str,
        payload: &Value,
    ) -> HostResult<Vec<Value>> {
        let Some(value) = payload.get("attachments") else {
            return Ok(Vec::new());
        };
        let Some(attachments) = value.as_array() else {
            return Err(HostError::format("attachments must be an array"));
        };
        if attachments.len() > 32 {
            return Err(HostError::format(
                "A chat message may contain at most 32 attachments.",
            ));
        }
        let chat = self
            .runtime_store
            .agent_chat(chat_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::conflict("chatNotFound", "Unknown chat.", json!({})))?;
        let workspace = self
            .runtime_store
            .find_workspace(&chat.workspace_id)
            .await
            .map_err(|error| HostError::state(error.to_string()))?
            .ok_or_else(|| HostError::state("The chat workspace no longer exists."))?;
        let workspace_root = canonical_directory(Path::new(&workspace.path))?;
        let mobile = caller.mobile
            || self
                .clients
                .get(&client_id)
                .is_some_and(|client| client.kind == ClientKind::Mobile);
        let mut validated = Vec::with_capacity(attachments.len());
        for attachment in attachments {
            if let Some(attachment_id) = attachment.get("attachmentId").and_then(Value::as_str) {
                validated.push(
                    self.resolve_chat_upload(caller, &chat.workspace_id, chat_id, attachment_id)
                        .await?,
                );
                continue;
            }
            let mut object = attachment
                .as_object()
                .cloned()
                .ok_or_else(|| HostError::format("attachment must be an object"))?;
            let attachment_type = object
                .get("type")
                .and_then(Value::as_str)
                .ok_or_else(|| HostError::format("attachment.type is required"))?;
            if !matches!(attachment_type, "file" | "localImage" | "image") {
                return Err(HostError::format("unsupported attachment type"));
            }
            let path_value = object.get("path").and_then(Value::as_str);
            let url = object.get("url").and_then(Value::as_str);
            if mobile && attachment_type == "image" && url.is_some() && path_value.is_none() {
                return Err(HostError::conflict(
                    "unsupported",
                    "Mobile chat attachments must use a completed local upload.",
                    json!({}),
                ));
            }
            let Some(path) = path_value.or(url) else {
                return Err(HostError::format("attachment path is required"));
            };
            if path.trim().is_empty() {
                return Err(HostError::format("attachment path is required"));
            }
            if url.is_some() && path_value.is_none() {
                if mobile {
                    return Err(HostError::conflict(
                        "unsupported",
                        "Mobile chat attachments must use a completed local upload.",
                        json!({}),
                    ));
                }
                if attachment_type != "image" {
                    return Err(HostError::conflict(
                        "unsupported",
                        "File attachments must resolve to a local workspace path.",
                        json!({}),
                    ));
                }
                validated.push(Value::Object(object));
                continue;
            }
            let resolved = resolve_attachment_path(path, &workspace_root)?;
            let canonical = resolved.canonicalize().map_err(|error| {
                HostError::format(format!("attachment path is unavailable: {error}"))
            })?;
            if mobile {
                super::mobile_workspace_file_paths::prompt_attachment_root(
                    &self.runtime_dir,
                    &canonical,
                )?;
            } else if !canonical.starts_with(&workspace_root) {
                return Err(HostError::conflict(
                    "unsupported",
                    "Attachment paths must be inside the chat workspace.",
                    json!({}),
                ));
            }
            object.insert(
                "path".into(),
                Value::String(canonical.to_string_lossy().into_owned()),
            );
            object.remove("url");
            validated.push(Value::Object(object));
        }
        Ok(validated)
    }
}

fn canonical_directory(path: &Path) -> HostResult<PathBuf> {
    path.canonicalize()
        .map_err(|error| HostError::state(format!("chat workspace is unavailable: {error}")))
}

fn resolve_attachment_path(path: &str, workspace_root: &Path) -> HostResult<PathBuf> {
    let candidate = Path::new(path);
    if candidate.is_absolute() {
        Ok(candidate.to_path_buf())
    } else {
        Ok(workspace_root.join(candidate))
    }
}
