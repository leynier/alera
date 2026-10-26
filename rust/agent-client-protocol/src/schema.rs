use serde_json::Value;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AcpProtocolGeneration {
    V1,
    V2,
}

#[derive(Debug, Clone, PartialEq)]
pub struct AcpCapabilities {
    pub raw: Value,
}

impl AcpCapabilities {
    pub fn supports(&self, path: &[&str]) -> bool {
        let mut value = &self.raw;
        for key in path {
            value = match value.get(*key) {
                Some(value) => value,
                None => return false,
            };
        }
        !matches!(value, Value::Null | Value::Bool(false))
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct AcpAuthMethod {
    pub id: String,
    pub name: String,
    pub kind: Option<String>,
    pub raw: Value,
}

#[derive(Debug, Clone, PartialEq)]
pub struct AcpInitializeResponse {
    pub protocol_version: u64,
    pub generation: AcpProtocolGeneration,
    pub capabilities: AcpCapabilities,
    pub auth_methods: Vec<AcpAuthMethod>,
    pub raw: Value,
}

impl AcpInitializeResponse {
    pub fn from_value(value: Value) -> Result<Self, crate::AcpError> {
        let object = value.as_object().ok_or_else(|| {
            crate::AcpError::Protocol("initialize result must be an object".into())
        })?;
        let protocol_version = object
            .get("protocolVersion")
            .and_then(Value::as_u64)
            .ok_or_else(|| crate::AcpError::Protocol("initialize lacks protocolVersion".into()))?;
        let generation = if object.get("info").is_some() || object.get("capabilities").is_some() {
            AcpProtocolGeneration::V2
        } else {
            AcpProtocolGeneration::V1
        };
        let capabilities = AcpCapabilities {
            raw: object
                .get("agentCapabilities")
                .or_else(|| object.get("capabilities"))
                .cloned()
                .unwrap_or_else(|| serde_json::json!({})),
        };
        let auth_methods = object
            .get("authMethods")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(|method| {
                Some(AcpAuthMethod {
                    id: method
                        .get("id")
                        .or_else(|| method.get("methodId"))?
                        .as_str()?
                        .to_owned(),
                    name: method.get("name")?.as_str()?.to_owned(),
                    kind: method
                        .get("type")
                        .and_then(Value::as_str)
                        .map(ToOwned::to_owned),
                    raw: method.clone(),
                })
            })
            .collect();
        Ok(Self {
            protocol_version,
            generation,
            capabilities,
            auth_methods,
            raw: value,
        })
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct AcpSessionResponse {
    pub session_id: Option<String>,
    pub config_options: Vec<Value>,
    pub raw: Value,
}

impl AcpSessionResponse {
    pub fn from_value(value: Value) -> Self {
        Self {
            session_id: value
                .get("sessionId")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned),
            config_options: value
                .get("configOptions")
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default(),
            raw: value,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct AcpPromptResponse {
    pub stop_reason: Option<String>,
    pub usage: Option<Value>,
    pub raw: Value,
}

impl AcpPromptResponse {
    pub fn from_value(value: Value) -> Self {
        Self {
            stop_reason: value
                .get("stopReason")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned),
            usage: value.get("usage").cloned(),
            raw: value,
        }
    }
}
