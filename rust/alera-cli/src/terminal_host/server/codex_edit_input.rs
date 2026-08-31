//! Keep structured input intact when replacing the visible prompt text.

use crate::terminal_host::host_error::{HostError, HostResult};
use serde_json::{json, Value};

pub(super) fn replace_prompt(payload: &mut Value, text: &str, retained: bool) -> HostResult<()> {
    // Attachment-only submissions may have model-only text for their paths.
    // In that case a new prompt must precede it, never replace that context.
    let attachment_only = retained
        && payload
            .pointer("/draft/text")
            .or_else(|| payload.pointer("/userMessage/text"))
            .and_then(Value::as_str)
            .is_some_and(|text| text.trim().is_empty());
    let input = payload
        .get_mut("input")
        .and_then(Value::as_array_mut)
        .ok_or_else(|| HostError::state("The original input is unavailable."))?;
    if input.iter().any(|item| {
        !matches!(
            item["type"].as_str(),
            Some("text" | "image" | "localImage" | "localAudio" | "skill" | "mention")
        )
    }) || !retained && input.iter().filter(|item| item["type"] == "text").count() != 1
    {
        return Err(HostError::state(
            "This older message cannot be reconstructed safely for editing.",
        ));
    }
    if attachment_only {
        input.insert(0, json!({"type": "text", "text": text}));
    } else if let Some(index) = input.iter().position(|item| item["type"] == "text") {
        let old_text = input[index]["text"]
            .as_str()
            .unwrap_or_default()
            .to_string();
        let mut elements = Vec::new();
        let mut preserved = Vec::new();
        for mut element in input[index]
            .get("text_elements")
            .or_else(|| input[index].get("textElements"))
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default()
        {
            let start = element
                .pointer("/byteRange/start")
                .and_then(Value::as_u64)
                .unwrap_or(u64::MAX) as usize;
            let end = element
                .pointer("/byteRange/end")
                .and_then(Value::as_u64)
                .unwrap_or(u64::MAX) as usize;
            let reference = old_text
                .get(start..end)
                .filter(|value| !value.is_empty())
                .ok_or_else(|| {
                    HostError::state("This message has an invalid structured reference.")
                })?;
            if let Some(offset) = text.find(reference) {
                element["byteRange"] = json!({"start": offset, "end": offset + reference.len()});
                elements.push(element);
            } else {
                element["byteRange"] = json!({"start": 0, "end": reference.len()});
                preserved
                    .push(json!({"type": "text", "text": reference, "text_elements": [element]}));
            }
        }
        input[index] = json!({"type": "text", "text": text, "text_elements": elements});
        input.extend(preserved);
    } else {
        input.insert(0, json!({"type": "text", "text": text}));
    }
    payload["userMessage"]["text"] = json!(text);
    if payload.get("draft").is_some() {
        payload["draft"]["text"] = json!(text);
    }
    Ok(())
}

pub(super) fn validate_retry(saved: &Value, request: &Value) -> HostResult<()> {
    for (key, pointer) in [
        ("text", "/userMessage/text"),
        ("turnId", "/editTargetTurnId"),
        ("itemId", "/editTargetItemId"),
    ] {
        if let Some(value) = request.get(key) {
            if value.as_str().is_none() || Some(value) != saved.pointer(pointer) {
                return Err(HostError::state(
                    "This edit operation already contains a different correction. Your revised text has not been saved. Reconcile or retry the original correction before starting a new edit.",
                ));
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preserves_attachment_input_and_unicode_reference_offsets() {
        let mut payload = json!({"input": [
            {"type":"skill", "name":"test", "path":"/skills/test"},
            {"type":"text", "text":"See @/tmp/a", "text_elements":[{"byteRange":{"start":4,"end":11},"placeholder":"a"}]},
            {"type":"localImage", "path":"/tmp/image"},
            {"type":"text", "text":"Attached context"}
        ],"userMessage":{},"draft":{"text":"See @/tmp/a"}});
        replace_prompt(&mut payload, "Sí @/tmp/a", true).unwrap();
        assert_eq!(
            payload["input"][1]["text_elements"][0]["byteRange"]["start"],
            4
        );
        assert_eq!(payload["input"][2]["path"], "/tmp/image");
        assert_eq!(payload["input"][3]["text"], "Attached context");
        replace_prompt(&mut payload, "No inline reference", true).unwrap();
        assert_eq!(payload["input"][4]["text"], "@/tmp/a");
    }

    #[test]
    fn rejects_ambiguous_legacy_input_without_mutation() {
        let mut payload =
            json!({"input":[{"type":"text","text":"first"},{"type":"text","text":"second"}]});
        let before = payload.clone();
        assert!(replace_prompt(&mut payload, "replacement", false).is_err());
        assert_eq!(payload, before);
    }

    #[test]
    fn editing_an_attachment_only_message_keeps_model_context() {
        let mut payload = json!({"draft":{"text":""},"userMessage":{"text":""},"input":[{"type":"text","text":"Attached file: /runtime/file.csv"}]});
        replace_prompt(&mut payload, "Please inspect it", true).unwrap();
        assert_eq!(payload["input"][0]["text"], "Please inspect it");
        assert_eq!(
            payload["input"][1]["text"],
            "Attached file: /runtime/file.csv"
        );
    }
}
