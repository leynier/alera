use anyhow::{Context as _, Result};
use chrono::{DateTime, Utc};
use sqlx::Row as _;

use super::{LocalAleraAccount, RuntimeStore};

impl RuntimeStore {
    pub async fn alera_account(&self) -> Result<Option<LocalAleraAccount>> {
        let row = sqlx::query(
            "SELECT accountId, email, providersJson, runtimeId, cloudBaseUrl, \
             signedInAt, accessTokenExpiresAt, pushSubscriptionCount \
             FROM aleraAccount WHERE id = 1",
        )
        .fetch_optional(self.pool())
        .await?;
        row.map(|row| {
            let providers_json: String = row.try_get("providersJson")?;
            Ok(LocalAleraAccount {
                account_id: row.try_get("accountId")?,
                email: row.try_get("email")?,
                providers: serde_json::from_str(&providers_json)?,
                runtime_id: row.try_get("runtimeId")?,
                cloud_base_url: row.try_get("cloudBaseUrl")?,
                signed_in_at: parse_timestamp(row.try_get("signedInAt")?)?,
                access_token_expires_at: parse_timestamp(row.try_get("accessTokenExpiresAt")?)?,
                push_subscription_count: row.try_get("pushSubscriptionCount")?,
            })
        })
        .transpose()
    }

    pub async fn set_alera_account(
        &self,
        account: &LocalAleraAccount,
    ) -> Result<LocalAleraAccount> {
        sqlx::query(
            "INSERT INTO aleraAccount \
             (id, accountId, email, providersJson, runtimeId, cloudBaseUrl, signedInAt, \
              accessTokenExpiresAt, pushSubscriptionCount) \
             VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?) \
             ON CONFLICT(id) DO UPDATE SET \
             accountId = excluded.accountId, email = excluded.email, \
             providersJson = excluded.providersJson, runtimeId = excluded.runtimeId, \
             cloudBaseUrl = excluded.cloudBaseUrl, signedInAt = excluded.signedInAt, \
             accessTokenExpiresAt = excluded.accessTokenExpiresAt, \
             pushSubscriptionCount = excluded.pushSubscriptionCount",
        )
        .bind(&account.account_id)
        .bind(&account.email)
        .bind(serde_json::to_string(&account.providers)?)
        .bind(&account.runtime_id)
        .bind(&account.cloud_base_url)
        .bind(account.signed_in_at.to_rfc3339())
        .bind(account.access_token_expires_at.to_rfc3339())
        .bind(account.push_subscription_count)
        .execute(self.pool())
        .await?;
        Ok(account.clone())
    }

    pub async fn clear_alera_account(&self) -> Result<()> {
        sqlx::query("DELETE FROM aleraAccount WHERE id = 1")
            .execute(self.pool())
            .await?;
        Ok(())
    }
}

fn parse_timestamp(value: String) -> Result<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(&value)
        .map(|value| value.with_timezone(&Utc))
        .with_context(|| format!("invalid account timestamp: {value}"))
}
