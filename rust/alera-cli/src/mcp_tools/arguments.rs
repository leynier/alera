//! Tool arguments checked against the tool's own schema before any CLI
//! argument is built, so a malformed call never reaches the runtime.

use serde_json::{Map, Value};

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("{0}")]
pub(crate) struct ToolInputError(pub(crate) String);

#[derive(Debug, Clone)]
pub(crate) struct ToolArguments {
    values: Map<String, Value>,
}

impl ToolArguments {
    pub(crate) fn parse(arguments: &Value, schema: &Value) -> Result<Self, ToolInputError> {
        let values = match arguments {
            Value::Null => Map::new(),
            Value::Object(values) => values.clone(),
            _ => return Err(ToolInputError("Tool arguments must be an object.".into())),
        };
        let properties = schema["properties"]
            .as_object()
            .cloned()
            .unwrap_or_default();
        for (name, value) in &values {
            let Some(property) = properties.get(name) else {
                return Err(ToolInputError(format!("Unknown argument `{name}`.")));
            };
            check_property(name, value, property)?;
        }
        for required in schema["required"].as_array().into_iter().flatten() {
            let Some(name) = required.as_str() else {
                continue;
            };
            if !values.contains_key(name) {
                return Err(ToolInputError(format!(
                    "Missing required argument `{name}`."
                )));
            }
        }
        Ok(Self { values })
    }

    pub(crate) fn string(&self, name: &str) -> Option<String> {
        self.values
            .get(name)
            .and_then(Value::as_str)
            .map(str::to_owned)
    }

    pub(crate) fn required(&self, name: &str) -> Result<String, ToolInputError> {
        self.string(name)
            .ok_or_else(|| ToolInputError(format!("Missing required argument `{name}`.")))
    }

    pub(crate) fn flag(&self, name: &str) -> bool {
        self.values
            .get(name)
            .and_then(Value::as_bool)
            .unwrap_or(false)
    }

    /// A boolean the caller may leave out, so `false` and absent differ.
    pub(crate) fn optional_flag(&self, name: &str) -> Option<bool> {
        self.values.get(name).and_then(Value::as_bool)
    }

    pub(crate) fn integer(&self, name: &str) -> Option<u64> {
        self.values.get(name).and_then(Value::as_u64)
    }

    /// A JSON object argument, such as a definition sent to the CLI on stdin.
    pub(crate) fn object(&self, name: &str) -> Option<&Map<String, Value>> {
        self.values.get(name).and_then(Value::as_object)
    }

    pub(crate) fn list(&self, name: &str) -> Option<Vec<String>> {
        self.values
            .get(name)
            .and_then(Value::as_array)
            .map(|items| {
                items
                    .iter()
                    .filter_map(Value::as_str)
                    .map(str::to_owned)
                    .collect()
            })
    }
}

fn check_property(name: &str, value: &Value, schema: &Value) -> Result<(), ToolInputError> {
    let invalid = |reason: &str| Err(ToolInputError(format!("Argument `{name}` {reason}.")));
    match schema["type"].as_str() {
        Some("string") => {
            let Some(text) = value.as_str() else {
                return invalid("must be a string");
            };
            if schema["minLength"]
                .as_u64()
                .is_some_and(|min| text.trim().len() < min as usize)
            {
                return invalid("cannot be empty");
            }
            if schema["maxLength"]
                .as_u64()
                .is_some_and(|max| text.chars().count() > max as usize)
            {
                return invalid("is too long");
            }
            if let Some(allowed) = schema["enum"].as_array() {
                if !allowed.iter().any(|item| item.as_str() == Some(text)) {
                    return invalid("has an unsupported value");
                }
            }
        }
        Some("boolean") if !value.is_boolean() => return invalid("must be a boolean"),
        Some("object") if !value.is_object() => return invalid("must be an object"),
        Some("integer") => {
            let Some(number) = value.as_u64() else {
                return invalid("must be a non-negative integer");
            };
            if schema["minimum"].as_u64().is_some_and(|min| number < min)
                || schema["maximum"].as_u64().is_some_and(|max| number > max)
            {
                return invalid("is out of range");
            }
        }
        Some("array") => {
            let Some(items) = value.as_array() else {
                return invalid("must be a list");
            };
            if items.is_empty() {
                return invalid("cannot be empty");
            }
            for item in items {
                check_property(name, item, &schema["items"])?;
            }
        }
        _ => {}
    }
    Ok(())
}
