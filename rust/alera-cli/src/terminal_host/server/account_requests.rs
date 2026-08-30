use std::sync::Arc;

use serde_json::{json, Value};
use tokio::sync::oneshot;

use crate::mobile_access::host_name;
use crate::terminal_host::alera_account::{
    bind_callback_listener, wait_for_callback, AleraAccountService, AuthProvider, Pkce,
};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{error_response, event, ok_response};

use super::request_payloads::parse_payload;
use super::requests::require_string_key;
use super::{ServerActor, ServerCommand};

#[derive(Debug, Clone, Copy)]
pub(crate) enum AccountOperation {
    Configuration,
    SignOut,
    Delete,
    Transfer,
    MobileEnrollment,
}

pub(crate) enum AccountCommand {
    SignInPrepared {
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
    },
    SignInCompleted {
        result: HostResult<Value>,
    },
    OperationFinished {
        client_id: u64,
        request_id: i64,
        operation: AccountOperation,
        result: HostResult<Value>,
    },
    SubscriptionSyncFinished {
        result: HostResult<usize>,
    },
}

#[derive(Debug, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct SignInRequest {
    provider: AuthProvider,
}

impl ServerActor {
    pub(super) async fn handle_account_command(&mut self, command: AccountCommand) {
        match command {
            AccountCommand::SignInPrepared {
                client_id,
                request_id,
                result,
            } => self.handle_account_sign_in_prepared(client_id, request_id, result),
            AccountCommand::SignInCompleted { result } => {
                self.handle_account_sign_in_completed(result).await
            }
            AccountCommand::OperationFinished {
                client_id,
                request_id,
                operation,
                result,
            } => {
                self.handle_account_operation_finished(client_id, request_id, operation, result)
                    .await
            }
            AccountCommand::SubscriptionSyncFinished { result } => {
                self.handle_push_subscription_sync_finished(result)
            }
        }
    }

    pub(super) fn try_start_account_request(
        &mut self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<bool> {
        match request_type {
            "account.signIn.start" | "account.link.start" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                if self.account_push.sign_in_cancel.is_some() {
                    return Err(HostError::state(
                        "An Alera account sign-in is already in progress.",
                    ));
                }
                let request: SignInRequest = parse_payload(payload)?;
                self.start_account_sign_in(
                    client_id,
                    request_id,
                    request.provider,
                    request_type == "account.link.start",
                );
                Ok(true)
            }
            "account.signOut" => {
                self.require_local_account_request(client_id, request_type)?;
                self.start_account_operation(
                    client_id,
                    request_id,
                    AccountOperation::SignOut,
                    async_account_sign_out(self.account_push.service.clone()),
                );
                Ok(true)
            }
            "account.delete" => {
                self.require_local_account_request(client_id, request_type)?;
                self.start_account_operation(
                    client_id,
                    request_id,
                    AccountOperation::Delete,
                    async_account_delete(self.account_push.service.clone()),
                );
                Ok(true)
            }
            "account.transfer.confirm" => {
                self.require_local_account_request(client_id, request_type)?;
                let target = require_string_key(payload, "targetAccountId")?;
                self.start_account_operation(
                    client_id,
                    request_id,
                    AccountOperation::Transfer,
                    async_account_transfer(self.account_push.service.clone(), target),
                );
                Ok(true)
            }
            "mobile.cloudEnrollment.create" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                let client = self
                    .clients
                    .get(&client_id)
                    .ok_or_else(|| HostError::state("Client disconnected."))?;
                let device_id = client.cloud_device_id.clone().ok_or_else(|| {
                    HostError::state(
                        "mobile.hello must include cloudDeviceId before cloud enrollment.",
                    )
                })?;
                let device_name = client
                    .mobile_device_name
                    .clone()
                    .unwrap_or_else(|| "Alera Mobile".to_string());
                self.start_account_operation(
                    client_id,
                    request_id,
                    AccountOperation::MobileEnrollment,
                    async_mobile_enrollment(
                        self.account_push.service.clone(),
                        device_id,
                        device_name,
                    ),
                );
                Ok(true)
            }
            "mobile.cloudSubscriptions.refresh" => {
                self.require_auth(client_id)?;
                self.require_request_allowed(client_id, request_type)?;
                self.start_push_subscription_sync(Some((client_id, request_id)));
                Ok(true)
            }
            _ => Ok(false),
        }
    }

    pub(super) async fn account_status(&self) -> HostResult<Value> {
        let account = self
            .account_push
            .service
            .local_account()
            .await
            .map_err(account_error)?;
        Ok(json!({
            "connected": account.is_some(),
            "account": account,
            "signInPending": self.account_push.sign_in_cancel.is_some(),
        }))
    }

    pub(super) fn cancel_account_sign_in(&mut self) -> Value {
        let cancelled = self
            .account_push
            .sign_in_cancel
            .take()
            .is_some_and(|cancel| cancel.send(()).is_ok());
        json!({ "cancelled": cancelled })
    }

    fn require_local_account_request(&self, client_id: u64, request_type: &str) -> HostResult<()> {
        self.require_auth(client_id)?;
        self.require_request_allowed(client_id, request_type)
    }

    fn start_account_sign_in(
        &mut self,
        client_id: u64,
        request_id: i64,
        provider: AuthProvider,
        linking: bool,
    ) {
        let (cancel_tx, cancel_rx) = oneshot::channel();
        self.account_push.sign_in_cancel = Some(cancel_tx);
        self.account_push.cloud_jobs += 1;
        self.cancel_shutdown_timer();
        let inbox = self.inbox.clone();
        let service = self.account_push.service.clone();
        tokio::spawn(async move {
            let preparation = prepare_sign_in(&service, provider, linking).await;
            let (listener, redirect_uri, pkce, transaction) = match preparation {
                Ok(value) => value,
                Err(error) => {
                    let _ = inbox.send(ServerCommand::Account(AccountCommand::SignInPrepared {
                        client_id,
                        request_id,
                        result: Err(account_error(error)),
                    }));
                    return;
                }
            };
            let _ = inbox.send(ServerCommand::Account(AccountCommand::SignInPrepared {
                client_id,
                request_id,
                result: Ok(json!({
                    "authorizationUrl": transaction.authorization_url,
                    "expiresAt": transaction.expires_at,
                    "provider": provider,
                })),
            }));
            let result = async {
                let code = wait_for_callback(listener, &transaction.state, cancel_rx).await?;
                service
                    .exchange_auth(
                        &transaction.transaction_id,
                        &transaction.state,
                        &code,
                        &pkce.verifier,
                    )
                    .await
            }
            .await
            .map(|account| json!(account))
            .map_err(account_error);
            let _ = redirect_uri;
            let _ = inbox.send(ServerCommand::Account(AccountCommand::SignInCompleted {
                result,
            }));
        });
    }

    pub(super) fn start_account_operation<F>(
        &mut self,
        client_id: u64,
        request_id: i64,
        operation: AccountOperation,
        future: F,
    ) where
        F: std::future::Future<Output = HostResult<Value>> + Send + 'static,
    {
        self.account_push.cloud_jobs += 1;
        self.cancel_shutdown_timer();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = future.await;
            let _ = inbox.send(ServerCommand::Account(AccountCommand::OperationFinished {
                client_id,
                request_id,
                operation,
                result,
            }));
        });
    }

    pub(super) fn handle_account_sign_in_prepared(
        &mut self,
        client_id: u64,
        request_id: i64,
        result: HostResult<Value>,
    ) {
        match result {
            Ok(payload) => self.client_write(client_id, ok_response(request_id, payload)),
            Err(error) => {
                self.client_write(client_id, error_response(request_id, &error));
                self.account_push.sign_in_cancel = None;
                self.account_push.cloud_jobs = self.account_push.cloud_jobs.saturating_sub(1);
                self.schedule_shutdown_if_idle();
            }
        }
    }

    pub(super) async fn handle_account_sign_in_completed(&mut self, result: HostResult<Value>) {
        self.account_push.sign_in_cancel = None;
        self.account_push.cloud_jobs = self.account_push.cloud_jobs.saturating_sub(1);
        match result {
            Ok(account) => {
                self.restart_remote_relay().await;
                self.broadcast_authenticated(event(
                    "aleraAccountChanged",
                    json!({ "connected": true, "account": account }),
                ));
                if self.account_push.push_enabled {
                    self.start_push_subscription_sync(None);
                }
            }
            Err(error) => self.broadcast_authenticated(event(
                "aleraAccountSignInFailed",
                json!({ "message": error.wire_message() }),
            )),
        }
        self.schedule_shutdown_if_idle();
    }

    pub(super) fn start_push_subscription_sync(&mut self, waiter: Option<(u64, i64)>) {
        if let Some(waiter) = waiter {
            self.account_push.subscription_sync_waiters.push(waiter);
        }
        if self.account_push.subscription_sync_in_flight {
            return;
        }
        self.account_push.subscription_sync_in_flight = true;
        self.account_push.cloud_jobs += 1;
        self.cancel_shutdown_timer();
        let inbox = self.inbox.clone();
        let service = self.account_push.service.clone();
        tokio::spawn(async move {
            let result = service
                .refresh_push_subscriptions()
                .await
                .map_err(account_error);
            let _ = inbox.send(ServerCommand::Account(
                AccountCommand::SubscriptionSyncFinished { result },
            ));
        });
    }

    pub(super) fn handle_push_subscription_sync_finished(&mut self, result: HostResult<usize>) {
        self.account_push.subscription_sync_in_flight = false;
        self.account_push.cloud_jobs = self.account_push.cloud_jobs.saturating_sub(1);
        let waiters = std::mem::take(&mut self.account_push.subscription_sync_waiters);
        match result {
            Ok(active_subscriptions) => {
                self.account_push.active_subscriptions = if self.account_push.push_enabled {
                    active_subscriptions
                } else {
                    0
                };
                for (client_id, request_id) in waiters {
                    self.client_write(
                        client_id,
                        ok_response(
                            request_id,
                            json!({ "activeSubscriptions": active_subscriptions }),
                        ),
                    );
                }
                self.broadcast_authenticated(event(
                    "mobilePushSubscriptionsChanged",
                    json!({ "activeSubscriptions": active_subscriptions }),
                ));
            }
            Err(error) => {
                if waiters.is_empty() {
                    eprintln!(
                        "alera push subscription sync failed: {}",
                        error.wire_message()
                    );
                } else {
                    for (client_id, request_id) in waiters {
                        self.client_write(client_id, error_response(request_id, &error));
                    }
                }
            }
        }
        self.schedule_shutdown_if_idle();
    }

    pub(super) async fn handle_account_operation_finished(
        &mut self,
        client_id: u64,
        request_id: i64,
        operation: AccountOperation,
        result: HostResult<Value>,
    ) {
        self.account_push.cloud_jobs = self.account_push.cloud_jobs.saturating_sub(1);
        match result {
            Ok(payload) => {
                self.client_write(client_id, ok_response(request_id, payload));
                if matches!(
                    operation,
                    AccountOperation::SignOut
                        | AccountOperation::Delete
                        | AccountOperation::Transfer
                ) {
                    self.stop_remote_relay().await;
                    self.account_push.active_subscriptions = 0;
                    self.broadcast_authenticated(event(
                        "aleraAccountChanged",
                        json!({ "connected": false }),
                    ));
                }
            }
            Err(error) => self.client_write(client_id, error_response(request_id, &error)),
        }
        self.schedule_shutdown_if_idle();
    }
}

async fn prepare_sign_in(
    service: &AleraAccountService,
    provider: AuthProvider,
    linking: bool,
) -> anyhow::Result<(
    tokio::net::TcpListener,
    String,
    Pkce,
    crate::terminal_host::alera_account::AuthTransaction,
)> {
    let (listener, redirect_uri) = bind_callback_listener().await?;
    let pkce = Pkce::generate();
    let transaction = if linking {
        service
            .create_link_transaction(provider, &redirect_uri, &pkce.challenge)
            .await?
    } else {
        service
            .create_auth_transaction(provider, &redirect_uri, &pkce.challenge, &host_name())
            .await?
    };
    Ok((listener, redirect_uri, pkce, transaction))
}

async fn async_account_sign_out(service: Arc<AleraAccountService>) -> HostResult<Value> {
    service.sign_out().await.map_err(account_error)?;
    Ok(json!({ "connected": false }))
}

async fn async_account_delete(service: Arc<AleraAccountService>) -> HostResult<Value> {
    service.delete_account().await.map_err(account_error)?;
    Ok(json!({ "deleted": true }))
}

async fn async_account_transfer(
    service: Arc<AleraAccountService>,
    target_account_id: String,
) -> HostResult<Value> {
    service
        .transfer_runtime(&target_account_id)
        .await
        .map_err(account_error)?;
    Ok(json!({
        "transferred": true,
        "reauthenticationRequired": true,
    }))
}

async fn async_mobile_enrollment(
    service: Arc<AleraAccountService>,
    device_id: String,
    device_name: String,
) -> HostResult<Value> {
    service
        .create_mobile_enrollment(&device_id, &device_name)
        .await
        .map(|enrollment| json!(enrollment))
        .map_err(account_error)
}

fn account_error(error: impl std::fmt::Display) -> HostError {
    HostError::state(error.to_string())
}
