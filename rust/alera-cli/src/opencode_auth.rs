use std::path::{Path, PathBuf};

use serde_json::Value;

pub(crate) const OPENCODE_GO_PROVIDER: &str = "opencode-go";
pub(crate) const OPENCODE_ZEN_PROVIDER: &str = "opencode";

pub(crate) async fn opencode_auth_key(provider: &str) -> Option<String> {
    for data_dir in opencode_data_dirs().await {
        let path = data_dir.join("auth.json");
        let Ok(raw) = tokio::fs::read_to_string(path).await else {
            continue;
        };
        let Ok(value) = serde_json::from_str(&raw) else {
            continue;
        };
        if let Some(key) = parse_opencode_auth_key(&value, provider) {
            return Some(key);
        }
    }
    None
}

pub(crate) fn parse_opencode_auth_key(value: &Value, provider: &str) -> Option<String> {
    let entry = value.get(provider)?;
    if entry.get("type").and_then(Value::as_str) != Some("api") {
        return None;
    }
    entry
        .get("key")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|key| !key.is_empty())
        .map(ToOwned::to_owned)
}

pub(crate) async fn opencode_data_dirs() -> Vec<PathBuf> {
    let explicit = crate::login_shell_environment::login_shell_variable("OPENCODE_DATA_DIR").await;
    let xdg_data_home = crate::login_shell_environment::login_shell_variable("XDG_DATA_HOME").await;
    let home = dirs::home_dir();
    let platform_data = if cfg!(any(target_os = "windows", target_os = "macos")) {
        dirs::data_local_dir()
    } else {
        None
    };
    opencode_data_dir_candidates(
        explicit.as_deref(),
        xdg_data_home.as_deref(),
        home.as_deref(),
        platform_data.as_deref(),
    )
}

pub(crate) fn opencode_data_dir_candidates(
    explicit: Option<&str>,
    xdg_data_home: Option<&str>,
    home: Option<&Path>,
    platform_data: Option<&Path>,
) -> Vec<PathBuf> {
    let mut paths = Vec::new();
    if let Some(value) = explicit {
        let path = PathBuf::from(value.trim());
        if !path.as_os_str().is_empty() {
            paths.push(path);
        }
        return paths;
    }
    if let Some(value) = xdg_data_home {
        let path = PathBuf::from(value.trim());
        if !path.as_os_str().is_empty() {
            paths.push(path.join("opencode"));
        }
    }
    if let Some(home) = home {
        paths.push(home.join(".local/share/opencode"));
    }
    if let Some(platform_data) = platform_data {
        paths.push(platform_data.join("opencode"));
    }
    let mut unique = Vec::with_capacity(paths.len());
    for path in paths {
        if !unique.iter().any(|candidate| candidate == &path) {
            unique.push(path);
        }
    }
    unique
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parses_api_credentials_without_exposing_other_auth_types() {
        let auth = json!({
            "opencode-go": { "type": "api", "key": "go-secret" },
            "opencode": { "type": "oauth", "access": "oauth-secret" }
        });
        assert_eq!(
            parse_opencode_auth_key(&auth, OPENCODE_GO_PROVIDER).as_deref(),
            Some("go-secret")
        );
        assert!(parse_opencode_auth_key(&auth, OPENCODE_ZEN_PROVIDER).is_none());
    }

    #[test]
    fn prefers_current_opencode_path_and_keeps_platform_fallbacks() {
        let paths = opencode_data_dir_candidates(
            None,
            Some("xdg"),
            Some(Path::new("home")),
            Some(Path::new("platform")),
        );
        assert_eq!(
            paths,
            vec![
                PathBuf::from("xdg/opencode"),
                PathBuf::from("home/.local/share/opencode"),
                PathBuf::from("platform/opencode"),
            ]
        );
    }

    #[test]
    fn explicit_data_directory_disables_fallback_search() {
        let paths = opencode_data_dir_candidates(
            Some(" custom "),
            Some("xdg"),
            Some(Path::new("home")),
            Some(Path::new("platform")),
        );
        assert_eq!(paths, vec![PathBuf::from("custom")]);
    }

    #[test]
    fn duplicate_home_platform_paths_are_removed() {
        let paths = opencode_data_dir_candidates(
            None,
            None,
            Some(Path::new("home")),
            Some(Path::new("home/.local/share")),
        );
        assert_eq!(paths, vec![PathBuf::from("home/.local/share/opencode")]);
    }
}
