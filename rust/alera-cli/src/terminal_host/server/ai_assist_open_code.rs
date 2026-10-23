use crate::terminal_host::orchestration::opencode_generation::OpenCodeGeneration;

/// `opencode run` for one AI Assist generation. v1 takes the thinking level
/// as `--variant`; OpenCode 2 has no such flag (its parser rejects unknown
/// flags) and reads it from the model as `provider/model#variant`.
pub(super) fn open_code_run_arguments(
    model: &str,
    thinking: Option<&str>,
    generation: OpenCodeGeneration,
) -> Vec<String> {
    let model = match (generation, thinking) {
        (OpenCodeGeneration::V2, Some(thinking)) => format!("{model}#{thinking}"),
        _ => model.to_string(),
    };
    let mut arguments = vec![
        "run".to_string(),
        "--model".to_string(),
        model,
        "--agent".to_string(),
        "build".to_string(),
        "--format".to_string(),
        "default".to_string(),
    ];
    if let (OpenCodeGeneration::V1, Some(thinking)) = (generation, thinking) {
        arguments.push("--variant".to_string());
        arguments.push(thinking.to_string());
    }
    arguments
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn each_generation_receives_the_thinking_level_its_own_way() {
        assert_eq!(
            open_code_run_arguments("opencode/x", Some("high"), OpenCodeGeneration::V1),
            [
                "run",
                "--model",
                "opencode/x",
                "--agent",
                "build",
                "--format",
                "default",
                "--variant",
                "high"
            ]
        );
        assert_eq!(
            open_code_run_arguments("opencode/x", Some("high"), OpenCodeGeneration::V2),
            [
                "run",
                "--model",
                "opencode/x#high",
                "--agent",
                "build",
                "--format",
                "default"
            ]
        );
        assert_eq!(
            open_code_run_arguments("opencode/x", None, OpenCodeGeneration::V2),
            [
                "run",
                "--model",
                "opencode/x",
                "--agent",
                "build",
                "--format",
                "default"
            ]
        );
    }
}
