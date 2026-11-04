//! Secret-field checks with a narrow exception for elicitation schema names.

use anyhow::Result;
use serde_json::Value;

use super::agent_chat_models::AgentChatStoreError;

const SECRET_KEYS: &[&str] = &[
    "authorization",
    "bearer",
    "bearertoken",
    "accesstoken",
    "refreshtoken",
    "idtoken",
    "apikey",
    "secret",
    "clientsecret",
    "password",
    "credentials",
    "mcpservers",
];

#[derive(Clone, Copy)]
enum Context {
    Strict,
    Snapshot,
    Requests,
    Request,
    Elicitation,
    Schema { sensitive: bool },
    SchemaMap { sensitive: bool },
    SchemaList { sensitive: bool },
}

fn is_secret_key(key: &str) -> bool {
    let folded: String = key
        .chars()
        .filter(|c| *c != '_' && *c != '-')
        .flat_map(char::to_lowercase)
        .collect();
    SECRET_KEYS.contains(&folded.as_str())
}

fn invalid(label: &str, key: &str) -> anyhow::Error {
    AgentChatStoreError::Invalid(format!("{label} must not carry `{key}`")).into()
}

fn is_schema_node(value: &Value) -> bool {
    match value {
        Value::Bool(_) => true,
        Value::Object(map) => map.keys().any(|key| {
            matches!(
                key.as_str(),
                "$ref"
                    | "$dynamicRef"
                    | "type"
                    | "properties"
                    | "patternProperties"
                    | "items"
                    | "allOf"
                    | "anyOf"
                    | "oneOf"
                    | "not"
                    | "if"
                    | "then"
                    | "else"
                    | "$defs"
                    | "definitions"
                    | "format"
                    | "title"
                    | "description"
            )
        }),
        _ => false,
    }
}

fn child_context(context: Context, key: &str) -> Context {
    match (context, key) {
        (Context::Snapshot, "pendingRequests") => Context::Requests,
        (Context::Request, "elicitation") => Context::Elicitation,
        (Context::Elicitation, "schema") => Context::Schema { sensitive: false },
        (Context::Schema { sensitive }, "properties" | "definitions" | "$defs") => {
            Context::SchemaMap { sensitive }
        }
        (
            Context::Schema { sensitive },
            "items"
            | "additionalItems"
            | "additionalProperties"
            | "unevaluatedItems"
            | "unevaluatedProperties"
            | "contains"
            | "not"
            | "if"
            | "then"
            | "else"
            | "propertyNames",
        ) => Context::Schema { sensitive },
        (Context::Schema { sensitive }, "allOf" | "anyOf" | "oneOf" | "prefixItems") => {
            Context::SchemaList { sensitive }
        }
        _ => Context::Strict,
    }
}

fn reject_in(label: &str, value: &Value, context: Context) -> Result<()> {
    match value {
        Value::Object(map) => {
            for (key, nested) in map {
                let secret = is_secret_key(key);
                if let Context::SchemaMap { sensitive } = context {
                    // Property and definition names describe input fields;
                    // only structural schema nodes get this exception.
                    if secret && !is_schema_node(nested) {
                        return Err(invalid(label, key));
                    }
                    reject_in(
                        label,
                        nested,
                        Context::Schema {
                            sensitive: sensitive || secret,
                        },
                    )?;
                    continue;
                }
                if secret {
                    return Err(invalid(label, key));
                }
                if let Context::Schema { sensitive: true } = context {
                    if matches!(key.as_str(), "default" | "const" | "enum" | "examples")
                        && !nested.is_null()
                    {
                        return Err(invalid(label, key));
                    }
                }
                reject_in(label, nested, child_context(context, key))?;
            }
            Ok(())
        }
        Value::Array(items) => {
            let child = match context {
                Context::Requests => Context::Request,
                Context::SchemaList { sensitive } => Context::Schema { sensitive },
                _ => Context::Strict,
            };
            items
                .iter()
                .try_for_each(|item| reject_in(label, item, child))
        }
        _ => Ok(()),
    }
}

pub(super) fn reject_secret_fields(label: &str, value: &Value) -> Result<()> {
    let context = if label == "snapshot" {
        Context::Snapshot
    } else {
        Context::Strict
    };
    reject_in(label, value, context)
}
