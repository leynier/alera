use std::path::Path;

pub(crate) fn repository_declares_automation(
    workspace_path: &str,
    project_repo_path: &str,
) -> bool {
    let candidates = [
        Path::new(workspace_path).join("alera.toml"),
        Path::new(project_repo_path).join("alera.toml"),
    ];
    candidates.iter().any(|path| {
        let Ok(contents) = std::fs::read_to_string(path) else {
            return false;
        };
        // toml 1.x FromStr for Value parses a single value, not a document.
        // A file like `automation_declared = true` must go through from_str.
        let Ok(value) = toml::from_str::<toml::Value>(&contents) else {
            return false;
        };
        let Some(root) = value.as_table() else {
            return false;
        };
        root.get("automation_declared")
            .and_then(toml::Value::as_bool)
            .unwrap_or(false)
            || root
                .get("automation")
                .and_then(toml::Value::as_table)
                .is_some_and(|table| {
                    table
                        .get("declared")
                        .or_else(|| table.get("enabled"))
                        .and_then(toml::Value::as_bool)
                        .unwrap_or(false)
                })
    })
}
