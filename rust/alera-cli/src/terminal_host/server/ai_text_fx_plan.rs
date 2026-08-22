use std::collections::HashMap;

use super::ai_text_requests::AiTextCommandPlan;

pub(super) fn plan_fx_command(selected_model: Option<&str>, prompt: &str) -> AiTextCommandPlan {
    let mut environment = HashMap::from([
        ("FX_PERMISSION_MODE".to_string(), "ask".to_string()),
        ("FX_AUTO_UPGRADE".to_string(), "0".to_string()),
        ("FX_HERDR".to_string(), "0".to_string()),
    ]);
    if let Some(model) = selected_model {
        environment.insert("FX_MODEL".to_string(), model.to_string());
    }
    AiTextCommandPlan {
        binary: "fx".to_string(),
        arguments: vec!["ask".to_string(), "--no-save".to_string()],
        stdin_payload: Some(prompt.to_string()),
        label: "fx".to_string(),
        environment,
        temporary_directory: None,
    }
}
