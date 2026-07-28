use std::{sync::Arc, time::Duration};

use async_trait::async_trait;
use chrono::{DateTime, TimeDelta, Utc};
use reqwest::Client;
use serde::Deserialize;
use tokio::sync::Mutex;
use url::Url;

#[async_trait]
pub trait GoogleAccessTokenProvider: Send + Sync {
    async fn access_token(&self) -> anyhow::Result<String>;
}

#[derive(Clone)]
pub struct MetadataAccessTokenProvider {
    client: Client,
    token_url: Url,
    cached: Arc<Mutex<Option<CachedToken>>>,
}

#[derive(Clone)]
struct CachedToken {
    value: String,
    refresh_after: DateTime<Utc>,
}

#[derive(Deserialize)]
struct MetadataTokenResponse {
    access_token: String,
    expires_in: i64,
}

impl MetadataAccessTokenProvider {
    pub fn new(token_url: Url, timeout: Duration) -> anyhow::Result<Self> {
        Ok(Self {
            client: Client::builder().timeout(timeout).build()?,
            token_url,
            cached: Arc::new(Mutex::new(None)),
        })
    }
}

#[async_trait]
impl GoogleAccessTokenProvider for MetadataAccessTokenProvider {
    async fn access_token(&self) -> anyhow::Result<String> {
        let mut cached = self.cached.lock().await;
        if let Some(token) = cached.as_ref() {
            if token.refresh_after > Utc::now() {
                return Ok(token.value.clone());
            }
        }

        let response = self
            .client
            .get(self.token_url.clone())
            .header("Metadata-Flavor", "Google")
            .send()
            .await?
            .error_for_status()?
            .json::<MetadataTokenResponse>()
            .await?;
        let safety_margin = 60_i64.min(response.expires_in.saturating_div(2));
        let refresh_after = Utc::now() + TimeDelta::seconds(response.expires_in - safety_margin);
        let value = response.access_token;
        *cached = Some(CachedToken {
            value: value.clone(),
            refresh_after,
        });
        Ok(value)
    }
}

#[cfg(test)]
#[derive(Clone)]
pub struct StaticAccessTokenProvider {
    pub token: String,
}

#[cfg(test)]
#[async_trait]
impl GoogleAccessTokenProvider for StaticAccessTokenProvider {
    async fn access_token(&self) -> anyhow::Result<String> {
        Ok(self.token.clone())
    }
}
