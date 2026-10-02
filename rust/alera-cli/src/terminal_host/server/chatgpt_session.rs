use futures_util::future::BoxFuture;
use serde_json::{json, Value};
use std::path::PathBuf;
use std::sync::{Arc, OnceLock};
use tokio::sync::{watch, Mutex};

use super::chatgpt_credentials::{Account, CredentialStore, Credentials};
use super::chatgpt_oauth::{self as oauth, Attempt, RESOURCE};
use crate::terminal_host::host_error::{HostError, HostResult};

static SESSION: OnceLock<Arc<ChatGptSession>> = OnceLock::new();

// The runtime owner lock guarantees one credential writer for this profile.
pub(super) fn initialize(directory: PathBuf) {
    SESSION.get_or_init(|| Arc::new(ChatGptSession::new(directory)));
}

pub(super) fn session() -> HostResult<Arc<ChatGptSession>> {
    SESSION
        .get()
        .cloned()
        .ok_or_else(|| HostError::state("ChatGPT is unavailable on this runtime."))
}

struct State {
    data: Option<Credentials>,
    pending: Option<tokio::task::JoinHandle<()>>,
    attempt_id: Option<String>,
    error: Option<String>,
}

pub(super) struct ChatGptSession {
    store: CredentialStore,
    state: Mutex<State>,
    changed: watch::Sender<u64>,
}

impl ChatGptSession {
    fn new(directory: PathBuf) -> Self {
        Self {
            store: CredentialStore::new(directory),
            state: Mutex::new(State {
                data: None,
                pending: None,
                attempt_id: None,
                error: None,
            }),
            changed: watch::channel(0).0,
        }
    }

    async fn load(&self, state: &mut State) -> HostResult<()> {
        if state.data.is_none() {
            state.data = Some(self.store.load().await?);
        }
        Ok(())
    }

    pub async fn status(&self) -> HostResult<Value> {
        let mut state = self.state.lock().await;
        self.load(&mut state).await?;
        let data = state.data.as_ref().unwrap();
        Ok(json!({
            "activeClientId": data.active,
            "pending": state.attempt_id.is_some(),
            "error": state.error,
            "showPlanNotice": !data.plan_notice_acknowledged && data.accounts.iter().any(|a| Some(&a.client_id) == data.active.as_ref() && a.tokens.as_ref().is_some_and(|t| t.can_infer())),
            "accounts": data.accounts.iter().enumerate().map(|(index, account)| json!({
                "clientId": account.client_id,
                "label": format!("{} ({})", if account.email.is_empty() { "ChatGPT" } else { &account.email }, index + 1),
                "connected": account.tokens.is_some(),
                "planEnabled": account.tokens.as_ref().is_some_and(|t| t.can_infer()),
            })).collect::<Vec<_>>()
        }))
    }

    pub async fn start(self: &Arc<Self>, client_id: Option<&str>) -> HostResult<Value> {
        let mut state = self.state.lock().await;
        self.load(&mut state).await?;
        Self::cancel_pending(&mut state);
        let data = state.data.as_ref().unwrap();
        let account = match client_id {
            Some(id) => Some(
                data.accounts
                    .iter()
                    .find(|a| a.client_id == id)
                    .cloned()
                    .ok_or_else(|| HostError::state("ChatGPT account was not found."))?,
            ),
            None => None,
        };
        let (attempt, url) = Attempt::prepare(&data.host_id, account).await?;
        let issued_registration = attempt.issued_registration.clone();
        let attempt_id = uuid::Uuid::new_v4().to_string();
        state.attempt_id = Some(attempt_id.clone());
        state.error = None;
        let session = self.clone();
        state.pending = Some(tokio::spawn(async move {
            let result =
                tokio::time::timeout(std::time::Duration::from_secs(300), attempt.finish())
                    .await
                    .unwrap_or_else(|_| {
                        Err(HostError::state("ChatGPT sign-in timed out. Try again."))
                    });
            let mut state = session.state.lock().await;
            if state.attempt_id.as_deref() != Some(&attempt_id) {
                return;
            }
            state.attempt_id = None;
            state.pending = None;
            let result = match result {
                Ok(account) => session.install(&mut state, account).await,
                Err(error) => Err(error),
            };
            if let Err(error) = result {
                // A code can expire after dynamic registration succeeds. Keep
                // the issued client for reauthorization, without trusting an identity.
                let issued = issued_registration.lock().unwrap().clone();
                if let Some(id) = issued {
                    let mut data = state.data.as_ref().unwrap().clone();
                    if !data.accounts.iter().any(|a| a.client_id == id) {
                        data.accounts.push(Account {
                            client_id: id,
                            subject: String::new(),
                            email: String::new(),
                            tokens: None,
                        });
                        if session.store.save(&data).await.is_ok() {
                            state.data = Some(data);
                        }
                    }
                }
                state.error = Some(error.to_string());
            }
        }));
        Ok(json!({"authorizationUrl": url}))
    }

    async fn install(&self, state: &mut State, account: Account) -> HostResult<()> {
        let mut data = state.data.as_ref().unwrap().clone();
        if let Some(existing) = data
            .accounts
            .iter_mut()
            .find(|a| a.client_id == account.client_id)
        {
            if !existing.subject.is_empty() && existing.subject != account.subject {
                return Err(HostError::state("ChatGPT account identity changed."));
            }
            *existing = account.clone();
        } else {
            data.accounts.push(account.clone());
        }
        data.active = Some(account.client_id);
        self.store.save(&data).await?;
        state.data = Some(data);
        self.changed.send_modify(|version| *version += 1);
        Ok(())
    }

    fn cancel_pending(state: &mut State) {
        if let Some(task) = state.pending.take() {
            task.abort();
        }
        state.attempt_id = None;
    }

    pub async fn cancel(&self) -> HostResult<Value> {
        Self::cancel_pending(&mut *self.state.lock().await);
        Ok(json!({"canceled": true}))
    }

    pub async fn acknowledge_plan(&self) -> HostResult<Value> {
        let mut state = self.state.lock().await;
        self.load(&mut state).await?;
        let mut data = state.data.as_ref().unwrap().clone();
        data.plan_notice_acknowledged = true;
        self.store.save(&data).await?;
        state.data = Some(data);
        Ok(json!({"acknowledged": true}))
    }

    pub async fn select(&self, id: &str) -> HostResult<Value> {
        let mut state = self.state.lock().await;
        self.load(&mut state).await?;
        let mut data = state.data.as_ref().unwrap().clone();
        if !data
            .accounts
            .iter()
            .any(|a| a.client_id == id && a.tokens.is_some())
        {
            return Err(HostError::state(
                "Continue with ChatGPT to reconnect this account.",
            ));
        }
        Self::cancel_pending(&mut state);
        let changed = data.active.as_deref() != Some(id);
        data.active = Some(id.to_string());
        self.store.save(&data).await?;
        state.data = Some(data);
        if changed {
            self.changed.send_modify(|version| *version += 1);
        }
        Ok(json!({"selected": true}))
    }

    pub async fn sign_out(&self, id: &str) -> HostResult<Value> {
        let mut state = self.state.lock().await;
        self.load(&mut state).await?;
        Self::cancel_pending(&mut state);
        let mut data = state.data.as_ref().unwrap().clone();
        let account = data
            .accounts
            .iter_mut()
            .find(|a| a.client_id == id)
            .ok_or_else(|| HostError::state("ChatGPT account was not found."))?;
        let refresh_token = account
            .tokens
            .as_ref()
            .and_then(|t| t.refresh_token.clone());
        account.tokens = None;
        let was_active = data.active.as_deref() == Some(id);
        if was_active {
            data.active = None;
        }
        // Stop requests even when the remote revocation service is unreachable.
        if was_active {
            self.changed.send_modify(|version| *version += 1);
        }
        state.data = Some(data.clone());
        self.store.save(&data).await?;
        let confirmed = match refresh_token {
            Some(token) => revoke(&token, id).await,
            None => true,
        };
        state.error = (!confirmed).then(|| "Signed out locally. Remote revocation was not confirmed; disconnect Alera in ChatGPT Settings.".to_string());
        Ok(json!({"signedOut": true, "revocationConfirmed": confirmed}))
    }

    pub async fn access(&self) -> HostResult<(String, watch::Receiver<u64>)> {
        self.access_with(
            |client_id, refresh_token| {
                Box::pin(async move {
                    oauth::token_request(&[
                        ("grant_type", "refresh_token"),
                        ("client_id", client_id.as_str()),
                        ("refresh_token", refresh_token.as_str()),
                        ("resource", RESOURCE),
                    ])
                    .await
                })
            },
            |token, client_id| {
                Box::pin(async move { oauth::verify_identity(&token, &client_id, None).await })
            },
        )
        .await
    }

    async fn access_with<'a>(
        &self,
        refresh: impl Fn(String, String) -> BoxFuture<'a, HostResult<Value>> + Send + Sync,
        verify: impl Fn(String, String) -> BoxFuture<'a, HostResult<oauth::Claims>> + Send + Sync,
    ) -> HostResult<(String, watch::Receiver<u64>)> {
        let mut state = self.state.lock().await;
        self.load(&mut state).await?;
        let data = state.data.as_mut().unwrap();
        let index = data
            .accounts
            .iter()
            .position(|a| Some(&a.client_id) == data.active.as_ref())
            .ok_or_else(|| {
                HostError::state("Connect a ChatGPT account in Settings > AI Assist.")
            })?;
        self.verify_pending_identity(data, index, &verify).await?;
        let account = &mut data.accounts[index];
        let tokens = account
            .tokens
            .as_ref()
            .ok_or_else(|| HostError::state("Continue with ChatGPT to reconnect this account."))?;
        if !tokens.can_infer() {
            return Err(HostError::state(
                "ChatGPT plan usage is disabled. Continue with ChatGPT to authorize it.",
            ));
        }
        if tokens.expires_at <= chrono::Utc::now().timestamp() + 60 {
            let refresh_token = tokens.refresh_token.as_deref().ok_or_else(|| {
                HostError::state("ChatGPT session expired. Continue with ChatGPT to sign in again.")
            })?;
            let result = refresh(account.client_id.clone(), refresh_token.to_string()).await;
            let value = match result {
                Ok(value) => value,
                Err(error) => {
                    if error.to_string().contains("ChatGPT session expired") {
                        account.tokens = None;
                        self.changed.send_modify(|version| *version += 1);
                        self.store.save(data).await?;
                    }
                    return Err(error);
                }
            };
            let mut renewed = oauth::parse_tokens(&value, Some(tokens))?;
            renewed.identity_pending = value.get("id_token").is_some();
            account.tokens = Some(renewed);
            // Rotation invalidates the previous refresh token. Persist its replacement
            // before fetching signing keys, but withhold access until identity verifies.
            self.store.save(data).await?;
            self.verify_pending_identity(data, index, &verify).await?;
        }
        let account = data
            .accounts
            .iter()
            .find(|a| Some(&a.client_id) == data.active.as_ref())
            .unwrap();
        let tokens = account.tokens.as_ref().unwrap();
        if !tokens.can_infer() {
            return Err(HostError::state(
                "ChatGPT plan usage is disabled. Reconnect to authorize it.",
            ));
        }
        Ok((tokens.access_token.clone(), self.changed.subscribe()))
    }

    async fn verify_pending_identity<'a>(
        &self,
        data: &mut Credentials,
        index: usize,
        verify: impl Fn(String, String) -> BoxFuture<'a, HostResult<oauth::Claims>> + Send + Sync,
    ) -> HostResult<()> {
        let account = &mut data.accounts[index];
        let Some(tokens) = account.tokens.as_ref().filter(|t| t.identity_pending) else {
            return Ok(());
        };
        let claims = verify(tokens.id_token.clone(), account.client_id.clone()).await?;
        if claims.sub != account.subject {
            account.tokens = None;
            self.changed.send_modify(|version| *version += 1);
            self.store.save(data).await?;
            return Err(HostError::state(
                "ChatGPT account identity changed during renewal.",
            ));
        }
        account.tokens.as_mut().unwrap().identity_pending = false;
        self.store.save(data).await
    }
}

async fn revoke(token: &str, client_id: &str) -> bool {
    let run = async {
        let client = oauth::client().ok()?;
        let discovery: Value = client
            .get(format!(
                "{}/.well-known/openid-configuration",
                oauth::ISSUER
            ))
            .send()
            .await
            .ok()?
            .error_for_status()
            .ok()?
            .json()
            .await
            .ok()?;
        let url = url::Url::parse(discovery.get("revocation_endpoint")?.as_str()?).ok()?;
        if url.origin().ascii_serialization() != oauth::ISSUER {
            return None;
        }
        let response = client
            .post(url)
            .form(&[
                ("token", token),
                ("token_type_hint", "refresh_token"),
                ("client_id", client_id),
            ])
            .send()
            .await
            .ok()?;
        Some(response.status() == reqwest::StatusCode::OK)
    };
    tokio::time::timeout(std::time::Duration::from_secs(10), run)
        .await
        .ok()
        .flatten()
        .unwrap_or(false)
}

#[cfg(test)]
#[path = "chatgpt_session_tests.rs"]
mod tests;
