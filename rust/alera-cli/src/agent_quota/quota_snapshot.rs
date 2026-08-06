#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct QuotaSnapshot {
    provider: String,
    account_id: String,
    display_name: String,
    status: String,
    updated_at: i64,
    error: Option<String>,
    windows: Vec<QuotaWindow>,
    buckets: Vec<QuotaBucket>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    amounts: Vec<QuotaAmount>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    data_quality: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    scope: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    rate_limit_reset_credits: Option<Box<CodexResetCredits>>,
}

impl QuotaSnapshot {
    fn unavailable(
        provider: &str,
        account_id: &str,
        display_name: &str,
        error: impl Into<String>,
    ) -> Self {
        Self {
            provider: provider.to_string(),
            account_id: account_id.to_string(),
            display_name: display_name.to_string(),
            status: "unavailable".to_string(),
            updated_at: now_millis(),
            error: Some(error.into()),
            windows: Vec::new(),
            buckets: Vec::new(),
            amounts: Vec::new(),
            data_quality: None,
            scope: None,
            rate_limit_reset_credits: None,
        }
    }

    fn error(
        provider: &str,
        account_id: &str,
        display_name: &str,
        error: impl Into<String>,
    ) -> Self {
        Self {
            provider: provider.to_string(),
            account_id: account_id.to_string(),
            display_name: display_name.to_string(),
            status: "error".to_string(),
            updated_at: now_millis(),
            error: Some(error.into()),
            windows: Vec::new(),
            buckets: Vec::new(),
            amounts: Vec::new(),
            data_quality: None,
            scope: None,
            rate_limit_reset_credits: None,
        }
    }

    fn ok(
        provider: &str,
        account_id: &str,
        display_name: &str,
        windows: Vec<QuotaWindow>,
        buckets: Vec<QuotaBucket>,
    ) -> Self {
        Self {
            provider: provider.to_string(),
            account_id: account_id.to_string(),
            display_name: display_name.to_string(),
            status: "ok".to_string(),
            updated_at: now_millis(),
            error: None,
            windows,
            buckets,
            amounts: Vec::new(),
            data_quality: None,
            scope: None,
            rate_limit_reset_credits: None,
        }
    }
}
