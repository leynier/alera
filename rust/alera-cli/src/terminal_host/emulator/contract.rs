use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum EmulatorPlatform {
    Android,
    Ios,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EmulatorDevice {
    pub id: String,
    pub platform: EmulatorPlatform,
    pub name: String,
    pub state: String,
    pub available: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub runtime: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GesturePoint {
    #[serde(rename = "type")]
    pub kind: Option<String>,
    pub x: f64,
    pub y: f64,
    pub edge: Option<u32>,
}

#[derive(Debug, Clone)]
pub struct EmulatorFailure {
    pub code: &'static str,
    pub message: String,
    pub next_steps: Vec<String>,
}

impl EmulatorFailure {
    pub fn new(
        code: &'static str,
        message: impl Into<String>,
        next_steps: impl IntoIterator<Item = impl Into<String>>,
    ) -> Self {
        Self {
            code,
            message: message.into(),
            next_steps: next_steps.into_iter().map(Into::into).collect(),
        }
    }

    pub fn dependency(name: &str, detail: impl Into<String>) -> Self {
        Self::new(
            "dependency_missing",
            detail,
            [format!("Install or configure {name}, then retry.")],
        )
    }

    pub fn invalid(message: impl Into<String>) -> Self {
        Self::new(
            "invalid_argument",
            message,
            ["Review `alera emulator --help` and retry."],
        )
    }

    pub fn unsupported(message: impl Into<String>) -> Self {
        Self::new(
            "unsupported_capability",
            message,
            ["Run `alera emulator --json capabilities` for supported operations."],
        )
    }

    pub fn to_json(&self) -> Value {
        json!({
            "ok": false,
            "error": {
                "code": self.code,
                "message": self.message,
                "nextSteps": self.next_steps,
            }
        })
    }
}

pub type EmulatorResult<T> = Result<T, EmulatorFailure>;

pub fn require_normalized(value: f64, name: &str) -> EmulatorResult<f64> {
    if value.is_finite() && (0.0..=1.0).contains(&value) {
        Ok(value)
    } else {
        Err(EmulatorFailure::invalid(format!(
            "{name} must be a finite value between 0 and 1."
        )))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalized_coordinates_reject_out_of_range_values() {
        assert!(require_normalized(0.5, "x").is_ok());
        assert!(require_normalized(-0.1, "x").is_err());
        assert!(require_normalized(f64::NAN, "x").is_err());
    }

    #[test]
    fn operational_failures_have_actionable_wire_shape() {
        let value = EmulatorFailure::dependency("Android Studio", "SDK missing").to_json();
        assert_eq!(value["ok"], false);
        assert_eq!(value["error"]["code"], "dependency_missing");
        assert!(value["error"]["nextSteps"].as_array().unwrap().len() == 1);
    }
}
