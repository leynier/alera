use super::AleraAccountService;
use anyhow::{Context as _, Result};

impl AleraAccountService {
    pub(crate) async fn configuration_request(
        &self,
        account_id: &str,
        action: &str,
        payload: serde_json::Value,
    ) -> Result<serde_json::Value> {
        let account = self
            .local_account()
            .await?
            .context("Sign in to Alera first.")?;
        anyhow::ensure!(
            account.account_id == account_id,
            "The selected Alera account changed."
        );
        let token = self.access_token().await?;
        anyhow::ensure!(
            self.local_account()
                .await?
                .is_some_and(|a| a.account_id == account_id),
            "The selected Alera account changed."
        );
        let (method, path, body) = match action {
            "head" => (reqwest::Method::GET, "/v1/configuration".to_string(), None),
            "history" => (
                reqwest::Method::GET,
                "/v1/configuration/history".to_string(),
                None,
            ),
            "revision" => (
                reqwest::Method::GET,
                format!(
                    "/v1/configuration/revisions/{}",
                    payload["revision"].as_u64().context("Invalid revision.")?
                ),
                None,
            ),
            "publish" => (
                reqwest::Method::POST,
                "/v1/configuration".to_string(),
                Some(payload),
            ),
            _ => anyhow::bail!("Unsupported configuration operation."),
        };
        self.cloud.json(method, &path, Some(&token), body).await
    }
}
