use super::{BrowserSettings, RuntimeAiAssistPromptSettings, RuntimeAiAssistSettings};
use anyhow::Result;
use serde_json::Value;

pub(super) fn overlay(previous: Option<&Value>, mut current: Value, key: &str) -> Result<Value> {
    let supported = match key {
        "browser.settings.v1" => serde_json::to_value(BrowserSettings::default())?,
        "settings.aiTextGeneration" => serde_json::to_value(RuntimeAiAssistSettings::default())?,
        _ => return Ok(current),
    };
    let previous = previous.unwrap_or(&Value::Null);
    if key == "settings.aiTextGeneration" {
        if let Some(prompts) = current.get_mut("promptSettingsByOperation") {
            *prompts = edit_field(
                &previous["promptSettingsByOperation"],
                prompts,
                "aiTextGeneration",
                "promptSettingsByOperation",
            )?;
        }
    }
    Ok(overlay_fields(previous, current, &supported))
}

pub(super) fn edit_field(
    previous: &Value,
    current: &Value,
    section: &str,
    key: &str,
) -> Result<Value> {
    match (section, key) {
        ("terminal", "colorOverrides") => Ok(overlay_fields(
            previous,
            current.clone(),
            &serde_json::json!({"foreground":null,"background":null,"cursor":null,"selection":null}),
        )),
        ("aiTextGeneration", "promptSettingsByOperation") => {
            let fields = serde_json::to_value(RuntimeAiAssistPromptSettings::default())?;
            let empty = serde_json::json!({});
            let Some(incoming) = current.as_object() else {
                return Ok(current.clone());
            };
            let mut result = incoming.clone();
            if let Some(prior) = previous.as_object() {
                for (operation, old) in prior {
                    let next = overlay_fields(
                        old,
                        incoming.get(operation).unwrap_or(&empty).clone(),
                        &fields,
                    );
                    if next.as_object().is_some_and(|value| value.is_empty())
                        && !incoming.contains_key(operation)
                    {
                        result.remove(operation);
                    } else {
                        result.insert(operation.clone(), next);
                    }
                }
            }
            Ok(Value::Object(result))
        }
        _ => Ok(current.clone()),
    }
}

fn overlay_fields(previous: &Value, current: Value, supported: &Value) -> Value {
    let Some(fields) = current.as_object() else {
        return current;
    };
    let mut result = previous.as_object().cloned().unwrap_or_default();
    result.retain(|key, _| supported.get(key).is_none());
    result.extend(fields.clone());
    Value::Object(result)
}
