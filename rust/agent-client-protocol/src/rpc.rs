use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum AcpRequestId {
    Null,
    Number(i64),
    String(String),
}

impl AcpRequestId {
    pub fn from_value(value: &Value) -> Result<Self, crate::AcpError> {
        match value {
            Value::Null => Ok(Self::Null),
            Value::Number(number) => number.as_i64().map(Self::Number).ok_or_else(|| {
                crate::AcpError::Protocol("ACP request id must be an integer".into())
            }),
            Value::String(value) => Ok(Self::String(value.clone())),
            _ => Err(crate::AcpError::Protocol(
                "ACP request id must be null, integer, or string".into(),
            )),
        }
    }

    pub fn as_value(&self) -> Value {
        match self {
            Self::Null => Value::Null,
            Self::Number(value) => Value::Number((*value).into()),
            Self::String(value) => Value::String(value.clone()),
        }
    }

    pub fn key(&self) -> String {
        match self {
            Self::Null => "$rpc:null".into(),
            Self::Number(value) => format!("$rpc:number:{value}"),
            Self::String(value) => format!("$rpc:string:{value}"),
        }
    }
}

impl std::fmt::Display for AcpRequestId {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Null => formatter.write_str("null"),
            Self::Number(value) => write!(formatter, "{value}"),
            Self::String(value) => formatter.write_str(value),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct RpcError {
    pub code: i64,
    pub message: String,
    pub data: Option<Value>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RpcRequest {
    pub id: AcpRequestId,
    pub method: String,
    pub params: Value,
    pub raw: Value,
}

#[derive(Debug, Clone, PartialEq)]
pub struct AcpResponse {
    pub id: AcpRequestId,
    pub result: Option<Value>,
    pub error: Option<RpcError>,
    pub raw: Value,
}

#[derive(Debug, Clone, PartialEq)]
pub enum AcpIncoming {
    Request(RpcRequest),
    Notification {
        method: String,
        params: Value,
        raw: Value,
    },
    /// A response for a call started with [`AcpClient::begin_prompt`].
    ///
    /// Prompt calls are intentionally fire-and-forget at the transport layer
    /// so peer requests can be answered while the turn is running. Returning
    /// the correlated response through the incoming stream lets adapters
    /// terminalize a turn even when the agent sends no follow-up notification.
    Response(AcpResponse),
}

pub fn request(id: AcpRequestId, method: &str, params: Value) -> Value {
    let mut object = Map::new();
    object.insert("jsonrpc".into(), Value::String("2.0".into()));
    object.insert("id".into(), id.as_value());
    object.insert("method".into(), Value::String(method.into()));
    object.insert("params".into(), params);
    Value::Object(object)
}

pub fn notification(method: &str, params: Value) -> Value {
    let mut object = Map::new();
    object.insert("jsonrpc".into(), Value::String("2.0".into()));
    object.insert("method".into(), Value::String(method.into()));
    object.insert("params".into(), params);
    Value::Object(object)
}

pub fn response(id: &AcpRequestId, result: Result<Value, RpcError>) -> Value {
    let mut object = Map::new();
    object.insert("jsonrpc".into(), Value::String("2.0".into()));
    object.insert("id".into(), id.as_value());
    match result {
        Ok(value) => {
            object.insert("result".into(), value);
        }
        Err(error) => {
            object.insert(
                "error".into(),
                serde_json::json!({
                    "code": error.code,
                    "message": error.message,
                    "data": error.data,
                }),
            );
        }
    }
    Value::Object(object)
}

pub fn classify(raw: Value) -> Result<Result<AcpIncoming, AcpResponse>, crate::AcpError> {
    let object = raw
        .as_object()
        .ok_or_else(|| crate::AcpError::Protocol("ACP frame must be an object".into()))?;
    if let Some(version) = object.get("jsonrpc") {
        if version.as_str() != Some("2.0") {
            return Err(crate::AcpError::Protocol("ACP jsonrpc must be 2.0".into()));
        }
    }
    if let Some(method) = object.get("method") {
        let method = method
            .as_str()
            .ok_or_else(|| crate::AcpError::Protocol("ACP method must be a string".into()))?
            .to_owned();
        let params = object.get("params").cloned().unwrap_or(Value::Null);
        if let Some(id) = object.get("id") {
            return Ok(Ok(AcpIncoming::Request(RpcRequest {
                id: AcpRequestId::from_value(id)?,
                method,
                params,
                raw,
            })));
        }
        return Ok(Ok(AcpIncoming::Notification {
            method,
            params,
            raw,
        }));
    }
    let id = object.get("id").ok_or_else(|| {
        crate::AcpError::Protocol("ACP frame is neither request nor response".into())
    })?;
    let id = AcpRequestId::from_value(id)?;
    let error = object.get("error").map(|value| RpcError {
        code: value.get("code").and_then(Value::as_i64).unwrap_or(-32603),
        message: value
            .get("message")
            .and_then(Value::as_str)
            .unwrap_or("ACP request failed")
            .to_owned(),
        data: value.get("data").cloned(),
    });
    let result = object.get("result").cloned();
    if result.is_none() && error.is_none() {
        return Err(crate::AcpError::Protocol(
            "ACP response must contain result or error".into(),
        ));
    }
    Ok(Err(AcpResponse {
        id,
        result,
        error,
        raw,
    }))
}

#[derive(Debug, Serialize, Deserialize)]
struct _JsonRpcVersion {
    jsonrpc: String,
}
