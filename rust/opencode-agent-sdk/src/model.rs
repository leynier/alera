use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OpenCodeResponse {
    pub status: u16,
    pub body: Value,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OpenCodeSession {
    pub id: String,
    #[serde(default)]
    pub title: Option<String>,
    #[serde(default)]
    pub directory: Option<String>,
    #[serde(default)]
    pub parent_id: Option<String>,
    pub raw: Value,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OpenCodeModel {
    pub provider_id: String,
    pub model_id: String,
    #[serde(default)]
    pub name: Option<String>,
    pub raw: Value,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OpenCodeEvent {
    pub event_type: String,
    #[serde(default)]
    pub session_id: Option<String>,
    pub payload: Value,
    pub raw: Value,
    #[serde(default)]
    pub terminal: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeRequest {
    pub id: String,
    pub kind: String,
    pub session_id: String,
    pub payload: Value,
}
