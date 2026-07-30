use std::{collections::HashMap, sync::Arc, time::Duration};

use anyhow::{anyhow, bail};
use async_trait::async_trait;
use reqwest::Client;
use serde::Deserialize;
use url::Url;

use crate::{
    api_models::ProviderKind, config::OAuthProviderConfig, google_oidc::GoogleIdTokenVerifier,
};

#[derive(Clone, Debug)]
pub struct ProviderIdentity {
    pub provider: ProviderKind,
    pub provider_user_id: String,
    pub email: String,
    pub email_verified: bool,
}

pub struct AuthorizationInput<'a> {
    pub redirect_uri: &'a str,
    pub state: &'a str,
    pub code_challenge: &'a str,
    pub nonce: Option<&'a str>,
}

pub struct ExchangeInput<'a> {
    pub code: &'a str,
    pub code_verifier: &'a str,
    pub redirect_uri: &'a str,
    pub expected_nonce: Option<&'a str>,
}

#[async_trait]
pub trait OAuthProvider: Send + Sync {
    fn kind(&self) -> ProviderKind;
    fn authorization_url(&self, input: AuthorizationInput<'_>) -> anyhow::Result<Url>;
    async fn exchange(&self, input: ExchangeInput<'_>) -> anyhow::Result<ProviderIdentity>;
}

#[derive(Clone)]
pub struct OAuthProviderRegistry {
    providers: HashMap<String, Arc<dyn OAuthProvider>>,
}

impl OAuthProviderRegistry {
    pub fn new(providers: Vec<Arc<dyn OAuthProvider>>) -> Self {
        Self {
            providers: providers
                .into_iter()
                .map(|provider| (provider.kind().as_str().to_owned(), provider))
                .collect(),
        }
    }

    pub fn get(&self, kind: ProviderKind) -> anyhow::Result<Arc<dyn OAuthProvider>> {
        self.providers
            .get(kind.as_str())
            .cloned()
            .ok_or_else(|| anyhow!("OAuth provider is not configured"))
    }
}

pub struct HttpOAuthProvider {
    kind: ProviderKind,
    config: OAuthProviderConfig,
    client: Client,
    google_id_tokens: Option<GoogleIdTokenVerifier>,
}

impl HttpOAuthProvider {
    pub fn new(
        kind: ProviderKind,
        config: OAuthProviderConfig,
        timeout: Duration,
    ) -> anyhow::Result<Self> {
        let client = Client::builder().timeout(timeout).build()?;
        let google_id_tokens = if kind == ProviderKind::Google {
            let jwks_url = config
                .jwks_url
                .clone()
                .ok_or_else(|| anyhow!("Google JWKS endpoint is not configured"))?;
            Some(GoogleIdTokenVerifier::new(
                client.clone(),
                config.client_id.clone(),
                jwks_url,
            )?)
        } else {
            None
        };
        Ok(Self {
            kind,
            config,
            client,
            google_id_tokens,
        })
    }

    fn google_authorization_url(&self, input: AuthorizationInput<'_>) -> anyhow::Result<Url> {
        let nonce = input
            .nonce
            .ok_or_else(|| anyhow!("Google authorization requires a nonce"))?;
        let mut url = self.config.authorization_url.clone();
        url.query_pairs_mut()
            .append_pair("client_id", &self.config.client_id)
            .append_pair("redirect_uri", input.redirect_uri)
            .append_pair("response_type", "code")
            .append_pair("scope", "openid email profile")
            .append_pair("access_type", "offline")
            .append_pair("prompt", "consent")
            .append_pair("state", input.state)
            .append_pair("nonce", nonce)
            .append_pair("code_challenge", input.code_challenge)
            .append_pair("code_challenge_method", "S256");
        Ok(url)
    }

    fn github_authorization_url(&self, input: AuthorizationInput<'_>) -> Url {
        let mut url = self.config.authorization_url.clone();
        url.query_pairs_mut()
            .append_pair("client_id", &self.config.client_id)
            .append_pair("redirect_uri", input.redirect_uri)
            .append_pair("scope", "read:user user:email")
            .append_pair("state", input.state)
            .append_pair("code_challenge", input.code_challenge)
            .append_pair("code_challenge_method", "S256");
        url
    }

    async fn exchange_google(&self, input: ExchangeInput<'_>) -> anyhow::Result<ProviderIdentity> {
        let token = self
            .client
            .post(self.config.token_url.clone())
            .form(&[
                ("client_id", self.config.client_id.as_str()),
                ("client_secret", self.config.client_secret.as_str()),
                ("code", input.code),
                ("code_verifier", input.code_verifier),
                ("grant_type", "authorization_code"),
                ("redirect_uri", input.redirect_uri),
            ])
            .send()
            .await?
            .error_for_status()?
            .json::<GoogleTokenResponse>()
            .await?;
        let claims = self
            .google_id_tokens
            .as_ref()
            .ok_or_else(|| anyhow!("Google ID token verifier is not configured"))?
            .verify(&token.id_token, input.expected_nonce)
            .await?;
        Ok(ProviderIdentity {
            provider: ProviderKind::Google,
            provider_user_id: claims.sub,
            email: normalize_email(&claims.email)?,
            email_verified: claims.email_verified,
        })
    }

    async fn exchange_github(&self, input: ExchangeInput<'_>) -> anyhow::Result<ProviderIdentity> {
        let token = self
            .client
            .post(self.config.token_url.clone())
            .header("Accept", "application/json")
            .form(&[
                ("client_id", self.config.client_id.as_str()),
                ("client_secret", self.config.client_secret.as_str()),
                ("code", input.code),
                ("code_verifier", input.code_verifier),
                ("redirect_uri", input.redirect_uri),
            ])
            .send()
            .await?
            .error_for_status()?
            .json::<GithubTokenResponse>()
            .await?;
        let user = self
            .github_get(self.config.user_url.clone(), &token.access_token)
            .await?
            .json::<GithubUser>()
            .await?;
        let emails_url = self
            .config
            .emails_url
            .clone()
            .ok_or_else(|| anyhow!("GitHub emails endpoint is not configured"))?;
        let emails = self
            .github_get(emails_url, &token.access_token)
            .await?
            .json::<Vec<GithubEmail>>()
            .await?;
        let email = emails
            .iter()
            .find(|value| value.primary)
            .or_else(|| emails.iter().find(|value| value.verified))
            .map(|value| (value.email.as_str(), value.verified))
            .or_else(|| user.email.as_deref().map(|value| (value, false)))
            .ok_or_else(|| anyhow!("GitHub account did not expose an email address"))?;

        Ok(ProviderIdentity {
            provider: ProviderKind::Github,
            provider_user_id: user.id.to_string(),
            email: normalize_email(email.0)?,
            email_verified: email.1,
        })
    }

    async fn github_get(&self, url: Url, access_token: &str) -> anyhow::Result<reqwest::Response> {
        Ok(self
            .client
            .get(url)
            .header("Accept", "application/vnd.github+json")
            .header("User-Agent", "Alera-Cloud")
            .header("X-GitHub-Api-Version", "2022-11-28")
            .bearer_auth(access_token)
            .send()
            .await?
            .error_for_status()?)
    }
}

#[async_trait]
impl OAuthProvider for HttpOAuthProvider {
    fn kind(&self) -> ProviderKind {
        self.kind
    }

    fn authorization_url(&self, input: AuthorizationInput<'_>) -> anyhow::Result<Url> {
        match self.kind {
            ProviderKind::Google => self.google_authorization_url(input),
            ProviderKind::Github => Ok(self.github_authorization_url(input)),
        }
    }

    async fn exchange(&self, input: ExchangeInput<'_>) -> anyhow::Result<ProviderIdentity> {
        match self.kind {
            ProviderKind::Google => self.exchange_google(input).await,
            ProviderKind::Github => self.exchange_github(input).await,
        }
    }
}

#[derive(Deserialize)]
struct GoogleTokenResponse {
    id_token: String,
}

#[derive(Deserialize)]
struct GithubTokenResponse {
    access_token: String,
}

#[derive(Deserialize)]
struct GithubUser {
    id: u64,
    email: Option<String>,
}

#[derive(Deserialize)]
struct GithubEmail {
    email: String,
    primary: bool,
    verified: bool,
}

fn normalize_email(value: &str) -> anyhow::Result<String> {
    let normalized = value.trim().to_lowercase();
    if normalized.is_empty() || !normalized.contains('@') || normalized.len() > 320 {
        bail!("identity provider returned an invalid email");
    }
    Ok(normalized)
}

#[cfg(test)]
mod tests {
    use super::normalize_email;

    #[test]
    fn normalizes_provider_email() {
        let email = normalize_email(" User@Example.COM ");
        assert!(email.is_ok());
        assert_eq!(email.ok().as_deref(), Some("user@example.com"));
    }
}
