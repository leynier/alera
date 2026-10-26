//! A bug report the person sends to the agent's vendor, in the shape of T3
//! Code's `ProviderAdapterV2.uploadFeedback`: the vendor receives the native
//! thread and the agent's logs, and answers with an id to quote.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FeedbackUploadInput {
    /// What went wrong, in the person's words. Blank text is treated as absent.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
}

impl FeedbackUploadInput {
    pub fn new(reason: Option<&str>) -> Self {
        Self {
            reason: reason
                .map(str::trim)
                .filter(|reason| !reason.is_empty())
                .map(str::to_owned),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FeedbackUploadResult {
    /// The vendor's id for the report.
    pub feedback_id: String,
}
