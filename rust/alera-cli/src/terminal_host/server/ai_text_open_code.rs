pub(super) fn open_code_run_arguments(model: &str, thinking: Option<&str>) -> Vec<String> {
    let mut arguments = vec![
        "run".to_string(),
        "--model".to_string(),
        model.to_string(),
        "--agent".to_string(),
        "build".to_string(),
        "--format".to_string(),
        "default".to_string(),
    ];
    if let Some(thinking) = thinking {
        arguments.push("--variant".to_string());
        arguments.push(thinking.to_string());
    }
    arguments
}
