use std::path::{Path, PathBuf};
use std::time::Duration;

use serde_json::Value;
use sqlx::sqlite::SqliteConnectOptions;
use sqlx::{ConnectOptions, Connection};

pub(crate) const OPENCODE_GO_PROVIDER: &str = "opencode-go";
pub(crate) const OPENCODE_ZEN_PROVIDER: &str = "opencode";
/// Only a Console connection's key can read the Go usage of its account.
const OPENCODE_CONSOLE_URL: &str = "https://opencode.ai/console";

/// OpenCode Go keys in the order to try them: the selected Console and Go keys
/// of OpenCode 2's credential database, then the auth.json Go key. Inline
/// `OPENCODE_AUTH_CONTENT` replaces both local stores.
pub(crate) async fn opencode_go_api_keys(database: Option<&Path>) -> Vec<String> {
    let inline = crate::login_shell_environment::login_shell_variable("OPENCODE_AUTH_CONTENT")
        .await
        .filter(|content| !content.trim().is_empty());
    match inline {
        Some(content) => {
            let auth = serde_json::from_str(&content).ok();
            let key = auth.and_then(|auth| parse_opencode_auth_key(&auth, OPENCODE_GO_PROVIDER));
            go_api_keys(None, key).await
        }
        None => go_api_keys(database, opencode_auth_key(OPENCODE_GO_PROVIDER).await).await,
    }
}

/// OpenCode 2 imports auth.json once, so a replaced Go key only exists in
/// the database, ahead of `auth_key`.
async fn go_api_keys(database: Option<&Path>, auth_key: Option<String>) -> Vec<String> {
    let mut keys = Vec::new();
    if let Some(database) = database {
        for integration in [OPENCODE_ZEN_PROVIDER, OPENCODE_GO_PROVIDER] {
            keys.extend(opencode_stored_api_key(database, integration).await);
        }
    }
    keys.extend(auth_key);
    let mut unique: Vec<String> = Vec::with_capacity(keys.len());
    for key in keys {
        if !unique.contains(&key) {
            unique.push(key);
        }
    }
    unique
}

/// The selected stored key of `integration_id`. The row is chosen before it
/// is decoded, so an OAuth or self-hosted connection cannot fall through to
/// another stored account; rows with a NULL `active` predate the flag.
async fn opencode_stored_api_key(database: &Path, integration_id: &str) -> Option<String> {
    if !tokio::fs::try_exists(database).await.unwrap_or(false) {
        return None;
    }
    let mut connection = SqliteConnectOptions::new()
        .filename(database)
        .read_only(true)
        .create_if_missing(false)
        .busy_timeout(Duration::from_millis(100))
        .connect()
        .await
        .ok()?;
    let value = sqlx::query_scalar::<_, Option<String>>(
        "SELECT value FROM credential \
         WHERE integration_id = ? AND active IS NOT 0 \
         ORDER BY active DESC, time_created DESC, id DESC LIMIT 1",
    )
    .bind(integration_id)
    .fetch_optional(&mut connection)
    .await;
    let _ = connection.close().await;
    parse_opencode_stored_key(&value.ok()???)
}

/// OpenCode 2 stores an API key as `{"type":"key","key":...}`, with the
/// server it belongs to in `metadata.server`.
fn parse_opencode_stored_key(raw: &str) -> Option<String> {
    let value: Value = serde_json::from_str(raw).ok()?;
    if value.get("type").and_then(Value::as_str) != Some("key") {
        return None;
    }
    let key = value.get("key")?.as_str()?.trim();
    match value.get("metadata") {
        None | Some(Value::Null) => {}
        Some(Value::Object(metadata)) => {
            if let Some(server) = metadata.get("server").and_then(Value::as_str) {
                if !is_opencode_console(server) {
                    return None;
                }
            }
        }
        Some(_) => return None,
    }
    (!key.is_empty()).then(|| key.to_owned())
}

fn is_opencode_console(server: &str) -> bool {
    reqwest::Url::parse(server).is_ok_and(|url| {
        format!(
            "{}{}",
            url.origin().ascii_serialization(),
            url.path().trim_end_matches('/')
        ) == OPENCODE_CONSOLE_URL
    })
}

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

    /// An OpenCode 2 credential database with `(id, integration, value,
    /// active, time_created)` rows.
    async fn credential_database(
        dir: &tempfile::TempDir,
        rows: &[(&str, &str, Value, Option<i64>, i64)],
    ) -> PathBuf {
        let path = dir.path().join("opencode.db");
        let mut connection = SqliteConnectOptions::new()
            .filename(&path)
            .create_if_missing(true)
            .connect()
            .await
            .unwrap();
        sqlx::query(
            "CREATE TABLE credential (id text PRIMARY KEY, integration_id text, value text, \
             active integer, time_created integer, time_updated integer)",
        )
        .execute(&mut connection)
        .await
        .unwrap();
        for (id, integration, value, active, created) in rows {
            sqlx::query("INSERT INTO credential VALUES (?, ?, ?, ?, ?, ?)")
                .bind(*id)
                .bind(*integration)
                .bind(value.to_string())
                .bind(*active)
                .bind(*created)
                .bind(*created)
                .execute(&mut connection)
                .await
                .unwrap();
        }
        connection.close().await.unwrap();
        path
    }

    fn key(key: &str) -> Value {
        json!({ "type": "key", "key": key })
    }

    #[tokio::test]
    async fn the_selected_stored_go_key_comes_before_the_imported_auth_json_key() {
        let dir = tempfile::tempdir().unwrap();
        let database = credential_database(
            &dir,
            &[
                (
                    "cred_imported",
                    OPENCODE_GO_PROVIDER,
                    key("imported-key"),
                    Some(0),
                    1,
                ),
                (
                    "cred_replaced",
                    OPENCODE_GO_PROVIDER,
                    key("replaced-key"),
                    Some(1),
                    2,
                ),
            ],
        )
        .await;
        assert_eq!(
            go_api_keys(Some(&database), Some("imported-key".into())).await,
            ["replaced-key", "imported-key"]
        );
        assert_eq!(
            go_api_keys(Some(&database), Some("replaced-key".into())).await,
            ["replaced-key"]
        );
        assert_eq!(
            go_api_keys(None, Some("imported-key".into())).await,
            ["imported-key"]
        );
        let missing = dir.path().join("missing.db");
        assert!(go_api_keys(Some(&missing), None).await.is_empty());
        assert!(!missing.exists());
    }

    #[tokio::test]
    async fn the_console_key_comes_first_and_selection_precedes_decoding() {
        let dir = tempfile::tempdir().unwrap();
        let console = json!({
            "type": "key", "key": " console-key ",
            "metadata": { "server": "https://opencode.ai/console/" },
        });
        let database = credential_database(
            &dir,
            &[
                ("cred_console", OPENCODE_ZEN_PROVIDER, console, None, 1),
                (
                    "cred_go_old",
                    OPENCODE_GO_PROVIDER,
                    key("old-go-key"),
                    None,
                    1,
                ),
                (
                    "cred_go_oauth",
                    OPENCODE_GO_PROVIDER,
                    json!({"type": "oauth"}),
                    None,
                    2,
                ),
            ],
        )
        .await;
        // The newest Go row is an OAuth connection, so no older key stands in.
        assert_eq!(
            go_api_keys(Some(&database), Some("auth-key".into())).await,
            ["console-key", "auth-key"]
        );
    }

    #[test]
    fn stored_keys_of_other_servers_are_ignored() {
        let stored = |metadata: Value| {
            parse_opencode_stored_key(
                &json!({ "type": "key", "key": "secret", "metadata": metadata }).to_string(),
            )
        };
        assert_eq!(stored(Value::Null).as_deref(), Some("secret"));
        assert_eq!(stored(json!({})).as_deref(), Some("secret"));
        assert_eq!(
            stored(json!({ "server": "https://opencode.ai:443/console" })).as_deref(),
            Some("secret")
        );
        assert!(stored(json!({ "server": "https://self-hosted.example/console" })).is_none());
        assert!(stored(json!({ "server": "not a url" })).is_none());
        assert!(stored(json!("server")).is_none());
        assert!(
            parse_opencode_stored_key(&json!({"type": "api", "key": "k"}).to_string()).is_none()
        );
        assert!(parse_opencode_stored_key(&key("  ").to_string()).is_none());
    }

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
