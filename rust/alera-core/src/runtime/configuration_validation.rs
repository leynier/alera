use super::{RuntimeAiAssistSettings, RuntimeTextActionsSettings};
use anyhow::{bail, Result};
use serde_json::Value;

pub(super) fn validate_document(document: &Value) -> Result<()> {
    if document["schemaVersion"] != 1
        || ["shared", "desktop", "mobile"]
            .iter()
            .any(|k| !document[k].is_object())
        || serde_json::to_vec(document)?.len() > 512 * 1024
    {
        bail!("Unsupported configuration document.");
    }
    if let Some(settings) = document.pointer("/desktop/settings") {
        validate_settings(settings)?;
    }
    if let Some(catalog) = document.pointer("/shared/textActions") {
        let actions = super::configuration_store::ordered_items(catalog)?;
        let settings: RuntimeTextActionsSettings =
            serde_json::from_value(serde_json::json!({"actions": actions}))?;
        super::validate_text_actions_settings(&settings)?;
    }
    Ok(())
}

pub(super) fn validate_settings(settings: &Value) -> Result<()> {
    let sections = settings
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("Invalid desktop settings."))?;
    for (section, fields) in sections {
        if !matches!(
            section.as_str(),
            "general"
                | "terminal"
                | "editor"
                | "keyboard"
                | "agents"
                | "aiTextGeneration"
                | "aiDictation"
        ) {
            continue;
        }
        let fields = fields
            .as_object()
            .ok_or_else(|| anyhow::anyhow!("Invalid settings section."))?;
        for (key, value) in fields {
            let variants: &[&str] = match (section.as_str(), key.as_str()) {
                ("terminal", "cursorShape") => &["block", "bar", "underline"],
                ("terminal", "toolbarCorner") => {
                    &["topLeft", "topRight", "bottomLeft", "bottomRight"]
                }
                ("keyboard", "terminalPolicy") => &["appFirst", "terminalFirst"],
                ("aiDictation", "transcriptionEngine") => &[
                    "localWhisper",
                    "codexSubscription",
                    "openAiCompatible",
                    "systemOnDevice",
                    "systemRecognition",
                ],
                ("aiDictation", "rewriteMode") => &["off", "cleanUp", "summarize"],
                ("aiDictation", "providerPolicy") => &["localOnly", "localPreferred"],
                ("aiDictation", "remoteProvider") => &["openAiCompatible"],
                _ => &[],
            };
            if !variants.is_empty() && !value.as_str().is_some_and(|v| variants.contains(&v)) {
                bail!("Unsupported setting: {section}.{key}. Update Alera before importing.");
            }
            match key.as_str() {
                "confirmProjectRemoval"
                | "confirmWorkspaceRemoval"
                | "showTrayIcon"
                | "showDockBadge"
                | "showTrayBadge"
                | "cursorBlink"
                | "clipboardOnSelect"
                | "allowOsc52Clipboard"
                | "showComposerByDefault"
                | "autosaveEnabled"
                | "agentStatusNotificationsEnabled"
                | "agentStatusFinishedNotificationsEnabled"
                | "enabled"
                | "hostFallbackEnabled"
                | "providerFallbackEnabled"
                | "planMode" => {
                    if !value.is_boolean() {
                        bail!("Invalid boolean setting: {key}");
                    }
                }
                "fontSize" | "lineHeight" | "paddingX" | "paddingY" | "cursorOpacity"
                | "backgroundOpacity" => {
                    if !value
                        .as_f64()
                        .is_some_and(|v| v.is_finite() && (0.0..=200.0).contains(&v))
                    {
                        bail!("Invalid numeric setting: {key}");
                    }
                }
                "fontWeight"
                | "tabSize"
                | "autosaveDelaySeconds"
                | "timeoutSeconds"
                | "tuiScrollSensitivity" => {
                    if value.as_u64().is_none_or(|v| v > 10000) {
                        bail!("Invalid integer setting: {key}");
                    }
                }
                "fontFamily"
                | "themeName"
                | "cursorShape"
                | "toolbarCorner"
                | "terminalPolicy"
                | "transcriptionEngine"
                | "rewriteMode"
                | "providerPolicy"
                | "remoteProvider"
                | "reasoningEffort"
                | "speedMode"
                | "permissionMode"
                    if !value.is_string() =>
                {
                    bail!("Invalid text setting: {key}");
                }
                _ => {}
            }
        }
    }
    if let Some(ai) = settings.get("aiTextGeneration") {
        let settings: RuntimeAiAssistSettings = serde_json::from_value(ai.clone())?;
        super::validate_ai_assist_settings(&settings)?;
    }
    if let Some(overrides) = settings.pointer("/keyboard/overrides") {
        let overrides = overrides
            .as_object()
            .ok_or_else(|| anyhow::anyhow!("Invalid keyboard overrides."))?;
        for value in overrides.values() {
            if !value
                .as_array()
                .is_some_and(|a| a.iter().all(Value::is_string))
            {
                bail!("Invalid keyboard binding.");
            }
        }
    }

    Ok(())
}
