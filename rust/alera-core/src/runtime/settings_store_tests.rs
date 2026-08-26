use std::collections::HashMap;

use super::{
    RuntimeAiAssistSettings, RuntimeSettings, RuntimeStore, RuntimeTextAction,
    RuntimeTextActionsSettings,
};

#[test]
fn ai_assist_settings_keep_historical_json_key() {
    let settings = RuntimeSettings {
        ai_assist: Some(RuntimeAiAssistSettings::default()),
        ..RuntimeSettings::default()
    };
    let value = serde_json::to_value(&settings).unwrap();
    assert!(value.get("aiTextGeneration").is_some());
    assert!(value.get("aiAssist").is_none());
}

#[tokio::test]
async fn text_actions_are_optional_and_round_trip_through_runtime_metadata() {
    let directory = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();

    assert!(store
        .runtime_settings()
        .await
        .unwrap()
        .text_actions
        .is_none());

    let runtime = store
        .set_text_actions_settings(RuntimeTextActionsSettings {
            actions: vec![RuntimeTextAction {
                id: " action-1 ".to_string(),
                name: " Polish ".to_string(),
                prompt: " Improve clarity. ".to_string(),
                enabled: true,
                agent_override: Some(" CODEX ".to_string()),
                model_override: Some(" gpt-5.5 ".to_string()),
                reasoning_by_model: HashMap::from([(
                    " gpt-5.5 ".to_string(),
                    " high ".to_string(),
                )]),
            }],
        })
        .await
        .unwrap();

    let action = &runtime.text_actions.unwrap().actions[0];
    assert_eq!(action.id, "action-1");
    assert_eq!(action.name, "Polish");
    assert_eq!(action.prompt, "Improve clarity.");
    assert_eq!(action.agent_override.as_deref(), Some("codex"));
    assert_eq!(action.model_override.as_deref(), Some("gpt-5.5"));
    assert_eq!(action.reasoning_by_model["gpt-5.5"], "high");

    let reopened = RuntimeStore::open(directory.path()).await.unwrap();
    assert_eq!(
        reopened
            .runtime_settings()
            .await
            .unwrap()
            .text_actions
            .unwrap()
            .actions
            .len(),
        1
    );
}
