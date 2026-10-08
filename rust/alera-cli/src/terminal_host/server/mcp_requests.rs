//! Host requests behind MCP Control: the access level, the runtime name,
//! connected apps, and the device sign-in.
//!
//! Only local clients may call these. Phones are refused by the mobile
//! allowlist and satellites by the hub reverse policy.

use std::sync::Arc;
use std::time::Duration;

use serde_json::{json, Value};
use tokio::sync::oneshot;

use crate::mcp_settings::{
    effective_runtime_name, mcp_access, runtime_name, set_mcp_access, set_runtime_name,
    validate_runtime_name, McpAccess,
};
use crate::terminal_host::alera_account::{AleraAccountService, DevicePoll};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::event;

use super::account_requests::{AccountCommand, AccountOperation};
use super::request_payloads::parse_payload;
use super::requests::require_string_key;
use super::{ServerActor, ServerCommand};

#[derive(Debug, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct McpSettingsUpdate {
    #[serde(default)]
    access: Option<String>,
    #[serde(default)]
    runtime_name: Option<String>,
}

impl ServerActor {
    pub(super) fn try_start_mcp_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<bool> {
        if !matches!(
            request_type,
            "mcp.settings.get"
                | "mcp.settings.update"
                | "mcp.grants.list"
                | "mcp.grants.revoke"
                | "account.signIn.device.start"
        ) {
            return Ok(false);
        }
        self.require_auth(client_id)?;
        self.require_request_allowed(client_id, request_type)?;
        let service = self.account_push.service.clone();
        let store = self.runtime_store.clone();
        match request_type {
            "mcp.settings.get" => {
                self.start_account_operation(
                    client_id,
                    request_id,
                    AccountOperation::McpSettingsRead,
                    async move { settings_snapshot(&service, &store).await },
                );
            }
            "mcp.settings.update" => {
                let update: McpSettingsUpdate = parse_payload(payload)?;
                let access =
                    match update.access.as_deref() {
                        Some(value) => Some(McpAccess::parse(value).ok_or_else(|| {
                            HostError::format("access must be off, read, or full")
                        })?),
                        None => None,
                    };
                let name = update
                    .runtime_name
                    .as_deref()
                    .map(validate_runtime_name)
                    .transpose()
                    .map_err(|error| HostError::format(error.to_string()))?;
                self.start_account_operation(
                    client_id,
                    request_id,
                    AccountOperation::McpSettingsUpdate,
                    async move { apply_settings(&service, &store, access, name).await },
                );
            }
            "mcp.grants.list" => {
                self.start_account_operation(
                    client_id,
                    request_id,
                    AccountOperation::McpGrants,
                    async move {
                        let grants = service.mcp_grants().await.map_err(cloud_error)?;
                        Ok(json!({ "grants": grants }))
                    },
                );
            }
            "mcp.grants.revoke" => {
                let grant_id = require_string_key(payload, "grantId")?;
                self.start_account_operation(
                    client_id,
                    request_id,
                    AccountOperation::McpGrants,
                    async move {
                        service
                            .revoke_mcp_grant(&grant_id)
                            .await
                            .map_err(cloud_error)?;
                        Ok(json!({ "revoked": true, "grantId": grant_id }))
                    },
                );
            }
            _ => self.start_device_sign_in(client_id, request_id)?,
        }
        Ok(true)
    }

    /// Completes `mcp.settings.update`: the link restarts so the cloud and the
    /// relay learn the new access level, then every client sees the change.
    pub(super) async fn finish_mcp_settings_update(&mut self, mut payload: Value) -> Value {
        self.restart_remote_relay().await;
        payload["relay"] = self.account_push.relay_status.clone();
        self.broadcast_authenticated(event("mcpSettingsChanged", payload.clone()));
        payload
    }

    pub(super) fn with_relay_status(&self, mut payload: Value) -> Value {
        payload["relay"] = self.account_push.relay_status.clone();
        payload
    }

    fn start_device_sign_in(&mut self, client_id: u64, request_id: i64) -> HostResult<()> {
        if self.account_push.sign_in_cancel.is_some() {
            return Err(HostError::state(
                "An Alera account sign-in is already in progress.",
            ));
        }
        let (cancel_tx, cancel_rx) = oneshot::channel();
        self.account_push.sign_in_cancel = Some(cancel_tx);
        self.account_push.last_sign_in = None;
        self.account_push.cloud_jobs += 1;
        self.cancel_shutdown_timer();
        let inbox = self.inbox.clone();
        let service = self.account_push.service.clone();
        tokio::spawn(async move {
            let name = service.runtime_display_name().await;
            let authorization = match service.start_device_sign_in(&name).await {
                Ok(authorization) => authorization,
                Err(error) => {
                    let _ = inbox
                        .send_wait(ServerCommand::Account(AccountCommand::SignInPrepared {
                            client_id,
                            request_id,
                            result: Err(cloud_error(error)),
                        }))
                        .await;
                    return;
                }
            };
            let expires_at =
                chrono::Utc::now() + chrono::Duration::seconds(authorization.expires_in);
            let _ = inbox
                .send_wait(ServerCommand::Account(AccountCommand::SignInPrepared {
                    client_id,
                    request_id,
                    result: Ok(json!({
                        "userCode": authorization.user_code,
                        "verificationUri": authorization.verification_uri,
                        "verificationUriComplete": authorization.verification_uri_complete,
                        "expiresAt": expires_at,
                        "runtimeName": name,
                    })),
                }))
                .await;
            let result = poll_device_sign_in(
                &service,
                &authorization.device_code,
                authorization.interval,
                expires_at,
                cancel_rx,
            )
            .await;
            let _ = inbox
                .send_wait(ServerCommand::Account(AccountCommand::SignInCompleted {
                    result,
                }))
                .await;
        });
        Ok(())
    }
}

async fn poll_device_sign_in(
    service: &AleraAccountService,
    device_code: &str,
    interval: i64,
    expires_at: chrono::DateTime<chrono::Utc>,
    mut cancelled: oneshot::Receiver<()>,
) -> HostResult<Value> {
    let mut interval = Duration::from_secs(interval.clamp(1, 60) as u64);
    loop {
        tokio::select! {
            _ = tokio::time::sleep(interval) => {}
            _ = &mut cancelled => return Err(HostError::state("The sign-in was cancelled.")),
        }
        if chrono::Utc::now() >= expires_at {
            return Err(HostError::state("The sign-in code expired. Start again."));
        }
        // The poll runs to completion even if cancelled meanwhile: dropping it
        // could lose a session the cloud already created, which would then
        // block the next device sign-in until it expires.
        let polled = service.poll_device_sign_in(device_code).await;
        if !matches!(polled, Ok(DevicePoll::Approved(_))) && cancelled.try_recv().is_ok() {
            return Err(HostError::state("The sign-in was cancelled."));
        }
        match polled {
            Ok(DevicePoll::Approved(envelope)) => {
                return if cancelled.try_recv().is_ok() {
                    Err(drop_cancelled_session(service, *envelope).await)
                } else {
                    save_session(service, *envelope).await
                };
            }
            Ok(DevicePoll::Pending { slow_down }) => {
                if slow_down {
                    interval += Duration::from_secs(5);
                }
            }
            Err(error) => return Err(cloud_error(error)),
        }
    }
}

/// The cloud already created this session, and a session nobody holds still
/// blocks the next device sign-in until it idles out. So it is revoked, or,
/// when revoking fails, kept so the person can sign out.
async fn drop_cancelled_session(
    service: &AleraAccountService,
    envelope: crate::terminal_host::alera_account::AuthEnvelope,
) -> HostError {
    if service.discard_session(&envelope).await.is_ok() {
        return HostError::state("The sign-in was cancelled.");
    }
    match service.complete_auth(envelope).await {
        Ok(_) => HostError::state(
            "The sign-in was cancelled after it was approved, and its session could not be revoked, so it was kept. Run `alera account logout` to remove it.",
        ),
        Err(error) => cloud_error(error),
    }
}

async fn save_session(
    service: &AleraAccountService,
    envelope: crate::terminal_host::alera_account::AuthEnvelope,
) -> HostResult<Value> {
    match service.complete_auth(envelope.clone()).await {
        Ok(account) => Ok(json!(account)),
        Err(error) => {
            // Not saved locally, so revoke it in the cloud rather than leave
            // an unreachable session behind.
            let _ = service.discard_session(&envelope).await;
            Err(cloud_error(error))
        }
    }
}

async fn settings_snapshot(
    service: &Arc<AleraAccountService>,
    store: &alera_core::runtime::RuntimeStore,
) -> HostResult<Value> {
    let access = mcp_access(store).await.map_err(store_error)?;
    let name = runtime_name(store).await.map_err(store_error)?;
    let account = service.local_account().await.map_err(store_error)?;
    Ok(json!({
        "access": access.as_str(),
        "runtimeName": name,
        "effectiveRuntimeName": effective_runtime_name(store).await,
        "accountConnected": account.is_some(),
        "runtimeId": service.runtime_id(),
    }))
}

async fn apply_settings(
    service: &Arc<AleraAccountService>,
    store: &alera_core::runtime::RuntimeStore,
    access: Option<McpAccess>,
    name: Option<String>,
) -> HostResult<Value> {
    if let Some(name) = name {
        // The cloud reserves the name, so renaming needs an account: a name
        // saved while signed out would reach the cloud at the next sign-in
        // without its uniqueness check.
        if service
            .local_account()
            .await
            .map_err(store_error)?
            .is_none()
        {
            return Err(HostError::state(
                "Sign in to an Alera account before renaming this runtime, so the name can be reserved.",
            ));
        }
        service.rename_runtime(&name).await.map_err(cloud_error)?;
        set_runtime_name(store, &name).await.map_err(store_error)?;
    }
    if let Some(access) = access {
        set_mcp_access(store, access).await.map_err(store_error)?;
        if service
            .local_account()
            .await
            .map_err(store_error)?
            .is_some()
        {
            if let Err(error) = service.report_capabilities().await {
                tracing::warn!("could not report MCP Control to the cloud: {error}");
            }
        }
    }
    settings_snapshot(service, store).await
}

fn store_error(error: impl std::fmt::Display) -> HostError {
    HostError::state(error.to_string())
}

fn cloud_error(error: anyhow::Error) -> HostError {
    match error.downcast_ref::<crate::terminal_host::alera_account::CloudRequestError>() {
        Some(request) => HostError::state(request.message().to_owned()),
        None => HostError::state(error.to_string()),
    }
}
