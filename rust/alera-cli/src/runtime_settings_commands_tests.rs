use alera_core::runtime::{RuntimeAiAssistSettings, RuntimeSettings};
use serde_json::json;

use super::{settings_update_payload, settings_view};

fn strings(values: &[&str]) -> Vec<String> {
    values.iter().map(|value| (*value).to_string()).collect()
}

fn configured() -> RuntimeSettings {
    let mut settings = RuntimeSettings {
        workspace_directory: Some("/work".into()),
        default_agent_profile_id: Some("prof_1".into()),
        ai_assist: Some(RuntimeAiAssistSettings {
            custom_command: "secret-tool --token abc".into(),
            ..RuntimeAiAssistSettings::default()
        }),
        ..RuntimeSettings::default()
    };
    settings.mobile_push_notifications.enabled = true;
    settings.voice.tts_voice = Some("nova".into());
    settings
}

#[test]
fn the_view_holds_only_allowlisted_settings() {
    let view = settings_view(&configured()).unwrap();
    assert_eq!(
        view,
        json!({
            "workspaceDirectory": "/work",
            "confirmProjectRemoval": true,
            "confirmWorkspaceRemoval": true,
            "defaultAgentProfileId": "prof_1",
            "aiAssist": {
                "enabled": true,
                "autoGenerateAgentTitles": true,
                "agent": "codex",
                "timeoutSeconds": 120,
            },
            "automation": {
                "startAtLogin": false,
                "runRetentionDays": 30,
                "auditRetentionDays": 90,
                "trashRetentionDays": 30,
            },
        })
    );
    let text = view.to_string();
    for hidden in [
        "secret-tool",
        "nova",
        "mobilePushNotifications",
        "agentQuotas",
    ] {
        assert!(!text.contains(hidden), "{hidden} leaked into {text}");
    }
}

#[test]
fn the_view_fills_ai_assist_defaults_when_it_was_never_configured() {
    let view = settings_view(&RuntimeSettings::default()).unwrap();
    assert_eq!(view["aiAssist"]["agent"], "codex");
    assert_eq!(view["workspaceDirectory"], serde_json::Value::Null);
}

#[test]
fn top_level_settings_are_sent_alone() {
    let payload = settings_update_payload(
        &configured(),
        &strings(&["confirmWorkspaceRemoval=false", "workspaceDirectory= /new "]),
        &strings(&["defaultAgentProfileId"]),
    )
    .unwrap();
    assert_eq!(
        payload,
        json!({
            "confirmWorkspaceRemoval": false,
            "workspaceDirectory": "/new",
            "defaultAgentProfileId": null,
        })
    );
}

#[test]
fn grouped_settings_keep_the_rest_of_their_object() {
    let payload = settings_update_payload(
        &configured(),
        &strings(&[
            "aiAssist.timeoutSeconds=45",
            "aiAssist.agent=claude",
            "automation.startAtLogin=true",
        ]),
        &[],
    )
    .unwrap();
    assert_eq!(payload["aiTextGeneration"]["timeoutSeconds"], 45);
    assert_eq!(payload["aiTextGeneration"]["agent"], "claude");
    assert_eq!(
        payload["aiTextGeneration"]["customCommand"],
        "secret-tool --token abc"
    );
    assert_eq!(payload["automation"]["autostart"], true);
    assert_eq!(payload["automation"]["runRetentionDays"], 30);
    assert!(payload.get("voice").is_none());
}

#[test]
fn keys_outside_the_allowlist_are_refused() {
    for assignment in [
        "aiAssist.customCommand=rm -rf /",
        "mobilePushNotifications.enabled=true",
        "voice.ttsVoice=nova",
        "agentQuotas=[]",
        "mcp.access=admin",
    ] {
        let error = settings_update_payload(&configured(), &strings(&[assignment]), &[])
            .unwrap_err()
            .to_string();
        assert!(error.contains("Unsupported runtime setting"), "{error}");
    }
}

#[test]
fn values_are_checked_before_reaching_the_host() {
    for (assignment, message) in [
        ("confirmProjectRemoval=yes", "true or false"),
        ("aiAssist.timeoutSeconds=5", "from 10 to 600"),
        ("automation.trashRetentionDays=0", "from 1 to 3650"),
        ("aiAssist.agent=custom", "must be one of"),
        ("workspaceDirectory=", "--unset"),
        ("confirmProjectRemoval", "key=value"),
    ] {
        let error = settings_update_payload(&configured(), &strings(&[assignment]), &[])
            .unwrap_err()
            .to_string();
        assert!(error.contains(message), "{assignment}: {error}");
    }
    let error = settings_update_payload(&configured(), &[], &strings(&["confirmProjectRemoval"]))
        .unwrap_err()
        .to_string();
    assert!(error.contains("cannot be unset"), "{error}");
    let error = settings_update_payload(
        &configured(),
        &strings(&["workspaceDirectory=/a"]),
        &strings(&["workspaceDirectory"]),
    )
    .unwrap_err()
    .to_string();
    assert!(error.contains("more than once"), "{error}");
}
