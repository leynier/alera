use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ModelSelection {
    pub id: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub params: Vec<ModelParameterValue>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelParameterValue {
    pub id: String,
    pub value: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelParameterDefinition {
    pub id: String,
    #[serde(default)]
    pub display_name: String,
    #[serde(default)]
    pub values: Vec<ModelParameterDefinitionValue>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelParameterDefinitionValue {
    pub value: String,
    #[serde(default)]
    pub display_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelVariant {
    #[serde(default)]
    pub params: Vec<ModelParameterValue>,
    #[serde(default)]
    pub display_name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub is_default: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SdkModel {
    pub id: String,
    #[serde(default)]
    pub display_name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub parameters: Vec<ModelParameterDefinition>,
    #[serde(default)]
    pub variants: Vec<ModelVariant>,
}
