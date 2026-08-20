use serde_json::{Map, Value};

pub(super) fn require_known_keys(
    values: &Map<String, Value>,
    allowed: &[&str],
) -> Result<(), String> {
    if let Some(key) = values.keys().find(|key| !allowed.contains(&key.as_str())) {
        return Err(format!("unsupported managed agent option: {key}"));
    }
    Ok(())
}

pub(super) fn push_string(
    values: &Map<String, Value>,
    key: &str,
    flag: &str,
    arguments: &mut Vec<String>,
) -> Result<(), String> {
    if let Some(value) = string_value(values, key)? {
        arguments.extend([flag.to_string(), value.to_string()]);
    }
    Ok(())
}

pub(super) fn push_enum(
    values: &Map<String, Value>,
    key: &str,
    flag: &str,
    allowed: &[&str],
    arguments: &mut Vec<String>,
) -> Result<(), String> {
    if let Some(value) = enum_value(values, key, allowed)? {
        arguments.extend([flag.to_string(), value.to_string()]);
    }
    Ok(())
}

pub(super) fn push_flag(
    values: &Map<String, Value>,
    key: &str,
    flag: &str,
    arguments: &mut Vec<String>,
) -> Result<(), String> {
    if bool_value(values, key)? == Some(true) {
        arguments.push(flag.to_string());
    }
    Ok(())
}

pub(super) fn string_value<'a>(
    values: &'a Map<String, Value>,
    key: &str,
) -> Result<Option<&'a str>, String> {
    let Some(value) = values.get(key) else {
        return Ok(None);
    };
    let value = value
        .as_str()
        .ok_or_else(|| format!("{key} must be a string."))?
        .trim();
    if value.is_empty() {
        return Err(format!("{key} must not be empty."));
    }
    Ok(Some(value))
}

pub(super) fn enum_value<'a>(
    values: &'a Map<String, Value>,
    key: &str,
    allowed: &[&str],
) -> Result<Option<&'a str>, String> {
    let Some(value) = string_value(values, key)? else {
        return Ok(None);
    };
    if allowed.contains(&value) {
        Ok(Some(value))
    } else {
        Err(format!("unsupported {key}: {value}"))
    }
}

pub(super) fn bool_value(values: &Map<String, Value>, key: &str) -> Result<Option<bool>, String> {
    values
        .get(key)
        .map(|value| {
            value
                .as_bool()
                .ok_or_else(|| format!("{key} must be a boolean."))
        })
        .transpose()
}

pub(super) fn push_positive_number(
    values: &Map<String, Value>,
    key: &str,
    flag: &str,
    arguments: &mut Vec<String>,
) -> Result<(), String> {
    let Some(value) = values.get(key) else {
        return Ok(());
    };
    let number = value
        .as_f64()
        .filter(|number| number.is_finite() && *number > 0.0)
        .ok_or_else(|| format!("{key} must be a positive number."))?;
    arguments.extend([flag.to_string(), number.to_string()]);
    Ok(())
}

pub(super) fn push_non_negative_integer(
    values: &Map<String, Value>,
    key: &str,
    flag: &str,
    arguments: &mut Vec<String>,
) -> Result<(), String> {
    let Some(value) = values.get(key) else {
        return Ok(());
    };
    let number = value
        .as_u64()
        .ok_or_else(|| format!("{key} must be a non-negative integer."))?;
    arguments.extend([flag.to_string(), number.to_string()]);
    Ok(())
}
