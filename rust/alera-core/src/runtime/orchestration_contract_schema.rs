use anyhow::{bail, Context, Result};
use serde_json::Value;

pub(super) const CONTRACT_MAX_BYTES: usize = 64 * 1024;
pub(super) const INSTANCE_MAX_BYTES: usize = 256 * 1024;

// Bound traversal before invoking the schema compiler. No refs, regexes or
// combinators are accepted, so validation cannot fetch or recursively expand.
pub(super) fn bounded_json(value: &Value, max_bytes: usize) -> Result<()> {
    let mut pending = vec![(value, 0)];
    let mut nodes = 0;
    let mut bytes = 0;
    while let Some((value, depth)) = pending.pop() {
        nodes += 1;
        if nodes > 4096 || depth > 24 {
            bail!("contract JSON exceeds the node or depth limit");
        }
        bytes += match value {
            Value::Object(values) => {
                pending.extend(values.values().map(|value| (value, depth + 1)));
                values.keys().map(|key| key.len() + 4).sum::<usize>() + 2
            }
            Value::Array(values) => {
                pending.extend(values.iter().map(|value| (value, depth + 1)));
                values.len() + 2
            }
            Value::String(value) => value.len() + 2,
            _ => 8,
        };
        if bytes > max_bytes {
            bail!("contract JSON exceeds the size limit");
        }
    }
    if serde_json::to_vec(value)?.len() > max_bytes {
        bail!("contract JSON exceeds the size limit");
    }
    Ok(())
}

pub(super) fn compile_schema(schema: &Value) -> Result<jsonschema::Validator> {
    bounded_json(schema, CONTRACT_MAX_BYTES)?;
    if schema.get("type").and_then(Value::as_str) != Some("object") {
        bail!("contract schema root must have type object");
    }
    let mut pending = vec![(schema, 0)];
    let mut nodes = 0;
    while let Some((schema, depth)) = pending.pop() {
        nodes += 1;
        if nodes > 128 || depth > 12 {
            bail!("contract schema exceeds the node or depth limit");
        }
        let object = schema
            .as_object()
            .context("contract schema must be an object")?;
        let kind = object
            .get("type")
            .and_then(Value::as_str)
            .context("every contract schema must declare one type")?;
        let keywords: &[&str] = match kind {
            "object" => &[
                "properties",
                "required",
                "additionalProperties",
                "minProperties",
                "maxProperties",
            ],
            "array" => &["items", "minItems", "maxItems"],
            "string" => &["minLength", "maxLength"],
            "integer" | "number" => &["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum"],
            "boolean" | "null" => &[],
            _ => bail!("unsupported contract schema type: {kind}"),
        };
        for key in object.keys() {
            if !["type", "title", "description", "enum", "const"].contains(&key.as_str())
                && !keywords.contains(&key.as_str())
            {
                bail!("unsupported contract schema keyword: {key}");
            }
        }
        if kind == "object" {
            if let Some(properties) = object.get("properties") {
                let properties = properties
                    .as_object()
                    .context("properties must be an object")?;
                pending.extend(properties.values().map(|schema| (schema, depth + 1)));
            }
            if let Some(required) = object.get("required") {
                for name in required.as_array().context("required must be an array")? {
                    let name = name
                        .as_str()
                        .context("required must contain property names")?;
                    if object
                        .get("properties")
                        .and_then(|props| props.get(name))
                        .is_none()
                    {
                        bail!("required property has no definition: {name}");
                    }
                }
            }
            if object
                .get("additionalProperties")
                .is_some_and(|value| !value.is_boolean())
            {
                bail!("additionalProperties must be a boolean");
            }
        }
        if kind == "array" {
            pending.push((
                object.get("items").context("array schema requires items")?,
                depth + 1,
            ));
        }
    }
    jsonschema::options()
        .with_draft(jsonschema::Draft::Draft202012)
        .build(schema)
        .map_err(|error| anyhow::anyhow!("invalid contract schema: {error}"))
}

pub(super) fn validate_instance(schema: &Value, instance: &Value, label: &str) -> Result<()> {
    bounded_json(instance, INSTANCE_MAX_BYTES)?;
    let validator = compile_schema(schema)?;
    // Do not echo the rejected instance: inputs and results can contain private data.
    if let Some(error) = validator.iter_errors(instance).next() {
        bail!(
            "contract {label} failed validation at {}",
            error.instance_path()
        );
    }
    Ok(())
}
