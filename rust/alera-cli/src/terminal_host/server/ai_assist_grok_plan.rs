use std::collections::HashMap;
use std::path::{Path, PathBuf};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::ai_assist_requests::AiAssistCommandPlan;

pub(super) fn plan_grok_command(
    model: &str,
    thinking: Option<&str>,
    prompt: &str,
) -> HostResult<AiAssistCommandPlan> {
    let directory = std::env::temp_dir().join(format!("alera-ai-assist-{}", uuid::Uuid::new_v4()));
    let grok_home = directory.join("grok-home");
    std::fs::create_dir_all(&grok_home)
        .map_err(|error| HostError::state(format!("Could not prepare Grok: {error}")))?;
    let prompt_file = directory.join("prompt.txt");
    std::fs::write(&prompt_file, prompt)
        .map_err(|error| HostError::state(format!("Could not prepare Grok prompt: {error}")))?;
    copy_grok_configuration(&grok_home);
    let mut arguments = vec![
        "--prompt-file".to_string(),
        prompt_file.to_string_lossy().into_owned(),
        "--output-format".to_string(),
        "plain".to_string(),
        "--model".to_string(),
        model.to_string(),
        "--tools".to_string(),
        String::new(),
        "--no-subagents".to_string(),
        "--disable-web-search".to_string(),
        "--no-memory".to_string(),
        "--max-turns".to_string(),
        "1".to_string(),
        "--verbatim".to_string(),
    ];
    if let Some(thinking) = thinking.filter(|value| *value != "default") {
        arguments.extend(["--effort".to_string(), thinking.to_string()]);
    }
    Ok(AiAssistCommandPlan {
        binary: "grok".to_string(),
        arguments,
        stdin_payload: None,
        label: "Grok Build".to_string(),
        environment: HashMap::from([(
            "GROK_HOME".to_string(),
            grok_home.to_string_lossy().into_owned(),
        )]),
        temporary_directory: Some(directory),
    })
}

fn copy_grok_configuration(target: &Path) {
    let source = std::env::var_os("GROK_HOME")
        .map(PathBuf::from)
        .or_else(|| dirs::home_dir().map(|home| home.join(".grok")));
    let Some(source) = source else {
        return;
    };
    for file_name in [
        "auth.json",
        "config.toml",
        "managed_config.toml",
        "requirements.toml",
    ] {
        let source_file = source.join(file_name);
        if source_file.is_file() {
            let _ = std::fs::copy(source_file, target.join(file_name));
        }
    }
}
