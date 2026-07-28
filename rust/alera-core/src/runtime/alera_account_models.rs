use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct LocalAleraAccount {
    pub account_id: String,
    pub email: String,
    pub providers: Vec<String>,
    pub runtime_id: String,
    pub cloud_base_url: String,
    pub signed_in_at: DateTime<Utc>,
    pub access_token_expires_at: DateTime<Utc>,
    #[serde(default)]
    pub push_subscription_count: i64,
}
