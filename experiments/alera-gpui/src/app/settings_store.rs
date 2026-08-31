use std::fs;
use std::path::PathBuf;
use std::thread;

use async_channel::{Receiver, Sender};
use serde_json::Value;
use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::Row as _;

use super::settings_state::SettingsState;

#[derive(Clone)]
pub(super) struct SettingsStore {
    updates: Sender<SettingsState>,
}

impl SettingsStore {
    #[cfg(all(test,feature="gpui-tests"))]
    pub(super) fn in_memory() -> Self {
        let (updates,_)=async_channel::unbounded();
        Self{updates}
    }

    pub fn start() -> (Self, SettingsState) {
        let path = settings_path();
        let initial = load_from_path(&path)
            .or_else(|| legacy_settings_fallback_path().and_then(|path| load_from_path(&path)))
            .unwrap_or_default();
        let (updates, receiver) = async_channel::unbounded();
        thread::Builder::new()
            .name("alera-gpui-settings".to_string())
            .spawn(move || persist_loop(path, receiver))
            .expect("failed to start the GPUI settings writer");
        (Self { updates }, initial)
    }

    pub fn save(&self, settings: &SettingsState) {
        let _ = self.updates.try_send(settings.clone());
    }
}

/// Load Flutter's local settings record without blocking the GPUI executor.
/// The runtime owns shared settings, while this database retains UI-only
/// fields such as quota pinning and selected Claude profiles.
pub(super) async fn load_shared_flutter_settings() -> Option<Value> {
    let path = crate::local_database_path()?;
    let (sender, receiver) = async_channel::bounded(1);
    thread::spawn(move || {
        let value = local_database_runtime()
            .and_then(|runtime| runtime.block_on(load_shared_flutter_settings_from(path)));
        let _ = sender.send_blocking(value);
    });
    receiver.recv().await.ok().flatten()
}

/// Persist UI-only quota fields in the same local record Flutter uses. The
/// runtime intentionally does not retain pinning and the selected Claude
/// profile, so writing only `runtimeSettings.update` would make the next
/// settings refresh resurrect stale values from Flutter's database.
pub(super) async fn save_shared_flutter_quota_settings(quotas: Value) -> Result<(), String> {
    let path = crate::local_database_path().ok_or("Flutter settings database is unavailable")?;
    let (sender, receiver) = async_channel::bounded(1);
    thread::spawn(move || {
        let result = local_database_runtime()
            .ok_or_else(|| "Could Not Create The Settings Database Runtime".to_owned())
            .and_then(|runtime| {
                runtime.block_on(update_shared_flutter_quota_settings(path, quotas))
            });
        let _ = sender.send_blocking(result);
    });
    receiver
        .recv()
        .await
        .map_err(|_| "The Settings Database Writer Stopped".to_owned())?
}

/// Merge local UI settings into Flutter's single JSON record. The update is
/// recursive for objects so a GPUI section edit preserves fields owned only by
/// Flutter and any future settings added to the same section.
pub(super) async fn save_shared_flutter_settings(updates: Value) -> Result<(), String> {
    let path = crate::local_database_path().ok_or("Flutter settings database is unavailable")?;
    let (sender, receiver) = async_channel::bounded(1);
    thread::spawn(move || {
        let result = local_database_runtime()
            .ok_or_else(|| "Could Not Create The Settings Database Runtime".to_owned())
            .and_then(|runtime| runtime.block_on(update_shared_flutter_settings(path, updates)));
        let _ = sender.send_blocking(result);
    });
    receiver
        .recv()
        .await
        .map_err(|_| "The Settings Database Writer Stopped".to_owned())?
}

fn persist_loop(path: PathBuf, receiver: Receiver<SettingsState>) {
    while let Ok(mut settings) = receiver.recv_blocking() {
        while let Ok(newer) = receiver.try_recv() {
            settings = newer;
        }
        if let Err(error) = write_to_path(&path, &settings) {
            crate::app_log::error(
                "settings_store",
                &format!("failed to persist GPUI settings: {error}"),
            );
        }
    }
}

fn settings_path() -> PathBuf {
    let app_id = std::env::var("ALERA_APP_ID")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| "dev.leynier.alera".to_owned());
    let scope = app_id
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || matches!(character, '.' | '-' | '_') {
                character
            } else {
                '_'
            }
        })
        .collect::<String>();
    settings_directory().join(format!("gpui-settings-{scope}.json"))
}

fn legacy_settings_fallback_path() -> Option<PathBuf> {
    let app_id = std::env::var("ALERA_APP_ID").ok();
    if app_id
        .as_deref()
        .is_some_and(|app_id| !matches!(app_id, "dev.leynier.alera" | "dev.leynier.alera.dev"))
    {
        return None;
    }
    Some(settings_directory().join("gpui-settings.json"))
}

fn settings_directory() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("Alera")
}

async fn load_shared_flutter_settings_from(path: PathBuf) -> Option<Value> {
    if !path.is_file() {
        return None;
    }
    let options = SqliteConnectOptions::new()
        .filename(path)
        .create_if_missing(false);
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect_with(options)
        .await
        .ok()?;
    let row = sqlx::query("SELECT data_json FROM app_settings_table WHERE id = 1")
        .fetch_optional(&pool)
        .await
        .ok()??;
    serde_json::from_str(row.get::<&str, _>("data_json")).ok()
}

async fn update_shared_flutter_quota_settings(path: PathBuf, quotas: Value) -> Result<(), String> {
    let options = SqliteConnectOptions::new()
        .filename(path)
        .create_if_missing(false);
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect_with(options)
        .await
        .map_err(|error| error.to_string())?;
    let current = sqlx::query("SELECT data_json FROM app_settings_table WHERE id = 1")
        .fetch_optional(&pool)
        .await
        .map_err(|error| error.to_string())?
        .and_then(|row| serde_json::from_str::<Value>(row.get::<&str, _>("data_json")).ok())
        .unwrap_or_else(|| serde_json::json!({}));
    let merged = merge_shared_flutter_quota_settings(current, &quotas)?;
    let data_json = serde_json::to_string(&merged).map_err(|error| error.to_string())?;
    sqlx::query(
        "INSERT INTO app_settings_table (id, data_json) VALUES (1, ?) \
         ON CONFLICT(id) DO UPDATE SET data_json = excluded.data_json",
    )
    .bind(data_json)
    .execute(&pool)
    .await
    .map_err(|error| error.to_string())?;
    Ok(())
}

async fn update_shared_flutter_settings(path: PathBuf, updates: Value) -> Result<(), String> {
    let options = SqliteConnectOptions::new()
        .filename(path)
        .create_if_missing(false);
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect_with(options)
        .await
        .map_err(|error| error.to_string())?;
    let current = sqlx::query("SELECT data_json FROM app_settings_table WHERE id = 1")
        .fetch_optional(&pool)
        .await
        .map_err(|error| error.to_string())?
        .and_then(|row| serde_json::from_str::<Value>(row.get::<&str, _>("data_json")).ok())
        .unwrap_or_else(|| serde_json::json!({}));
    let merged = merge_shared_flutter_settings(current, updates)?;
    let data_json = serde_json::to_string(&merged).map_err(|error| error.to_string())?;
    sqlx::query(
        "INSERT INTO app_settings_table (id, data_json) VALUES (1, ?) \
         ON CONFLICT(id) DO UPDATE SET data_json = excluded.data_json",
    )
    .bind(data_json)
    .execute(&pool)
    .await
    .map_err(|error| error.to_string())?;
    Ok(())
}

fn merge_shared_flutter_settings(mut root: Value, updates: Value) -> Result<Value, String> {
    let root_object = root
        .as_object_mut()
        .ok_or_else(|| "Flutter settings record is not an object".to_owned())?;
    let updates = updates
        .as_object()
        .ok_or_else(|| "Flutter settings update is not an object".to_owned())?;
    for (section, update) in updates {
        let current = root_object
            .entry(section.clone())
            .or_insert_with(|| serde_json::json!({}));
        merge_json_value(current, update)?;
    }
    Ok(root)
}

fn merge_json_value(current: &mut Value, update: &Value) -> Result<(), String> {
    if let (Some(current), Some(update)) = (current.as_object_mut(), update.as_object()) {
        for (key, value) in update {
            let current_value = current.entry(key.clone()).or_insert(Value::Null);
            merge_json_value(current_value, value)?;
        }
        return Ok(());
    }
    *current = update.clone();
    Ok(())
}

fn merge_shared_flutter_quota_settings(mut root: Value, quotas: &Value) -> Result<Value, String> {
    let root_object = root
        .as_object_mut()
        .ok_or_else(|| "Flutter settings record is not an object".to_owned())?;
    let agents = root_object
        .entry("agents")
        .or_insert_with(|| serde_json::json!({}))
        .as_object_mut()
        .ok_or_else(|| "Flutter agents settings are not an object".to_owned())?;
    let quota_settings = agents
        .entry("quotas")
        .or_insert_with(|| serde_json::json!({}))
        .as_object_mut()
        .ok_or_else(|| "Flutter quota settings are not an object".to_owned())?;
    let hosts = quota_settings
        .entry("hosts")
        .or_insert_with(|| serde_json::json!({}))
        .as_object_mut()
        .ok_or_else(|| "Flutter quota hosts are not an object".to_owned())?;
    let local = hosts
        .entry("local")
        .or_insert_with(|| serde_json::json!({}))
        .as_object_mut()
        .ok_or_else(|| "Flutter local quota settings are not an object".to_owned())?;
    for key in [
        "enabledProviders",
        "claudeDefaultEnabled",
        "claudeDefaultShowInUsage",
        "claudeProfiles",
        "selectedClaudeProfile",
        "environment",
        "unpinnedQuotaKeys",
    ] {
        if let Some(value) = quotas.get(key) {
            local.insert(key.to_owned(), value.clone());
        }
    }
    Ok(root)
}

fn local_database_runtime() -> Option<tokio::runtime::Runtime> {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .ok()
}

fn load_from_path(path: &PathBuf) -> Option<SettingsState> {
    let bytes = fs::read(path).ok()?;
    let mut value = serde_json::from_slice::<serde_json::Value>(&bytes).ok()?;
    let object = value.as_object_mut()?;
    if !object.contains_key("settings_schema_version") {
        // Match Flutter's migration for settings written before the explicit
        // keep-runtime flag existed. Fresh installs still use the false default.
        object.insert(
            "keep_runtime_open_on_quit".to_string(),
            serde_json::Value::Bool(true),
        );
        object.insert(
            "settings_schema_version".to_string(),
            serde_json::Value::from(1),
        );
    }
    serde_json::from_value(value).ok()
}

fn write_to_path(path: &PathBuf, settings: &SettingsState) -> Result<(), String> {
    let parent = path
        .parent()
        .ok_or_else(|| "settings path has no parent".to_string())?;
    fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    let bytes = serde_json::to_vec_pretty(settings).map_err(|error| error.to_string())?;
    let temporary = path.with_extension("json.tmp");
    fs::write(&temporary, bytes).map_err(|error| error.to_string())?;
    fs::rename(&temporary, path).map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::{
        load_from_path, merge_shared_flutter_quota_settings, merge_shared_flutter_settings,
        write_to_path,
    };
    use crate::app::settings_state::SettingsState;

    #[test]
    fn settings_round_trip_preserves_local_controls() {
        let path = std::env::temp_dir().join(format!(
            "alera-gpui-settings-test-{}-{}.json",
            std::process::id(),
            std::thread::current().name().unwrap_or("thread")
        ));
        let settings = SettingsState {
            editor_theme: "Nord".to_string(),
            terminal_font_size: 15.0,
            terminal_clipboard_on_select: true,
            ..SettingsState::default()
        };

        write_to_path(&path, &settings).expect("settings write should succeed");
        let loaded = load_from_path(&path).expect("settings should load");
        assert_eq!(loaded.editor_theme, "Nord");
        assert_eq!(loaded.terminal_font_size, 15.0);
        assert!(loaded.terminal_clipboard_on_select);
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn legacy_settings_keep_the_runtime_open() {
        let path = std::env::temp_dir().join(format!(
            "alera-gpui-legacy-settings-test-{}-{}.json",
            std::process::id(),
            std::thread::current().name().unwrap_or("thread")
        ));
        std::fs::write(&path, r#"{"editor_theme":"Nord"}"#).expect("legacy settings write");

        let loaded = load_from_path(&path).expect("legacy settings should load");
        assert!(loaded.keep_runtime_open_on_quit);
        assert_eq!(loaded.settings_schema_version, 1);
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn shared_flutter_quota_merge_preserves_unrelated_settings() {
        let merged = merge_shared_flutter_quota_settings(
            json!({
                "general": {"workspaceDirectory": "~/workspaces"},
                "agents": {"quotas": {"hosts": {"local": {"unpinnedQuotaKeys": ["old"]}}}}
            }),
            &json!({
                "enabledProviders": ["codex", "kimi"],
                "claudeDefaultEnabled": true,
                "claudeProfiles": [],
                "selectedClaudeProfile": "default",
                "environment": {"HOME": "/tmp"},
                "unpinnedQuotaKeys": []
            }),
        )
        .expect("quota merge should succeed");

        assert_eq!(
            merged.pointer("/general/workspaceDirectory"),
            Some(&json!("~/workspaces"))
        );
        assert_eq!(
            merged.pointer("/agents/quotas/hosts/local/enabledProviders"),
            Some(&json!(["codex", "kimi"]))
        );
        assert_eq!(
            merged.pointer("/agents/quotas/hosts/local/unpinnedQuotaKeys"),
            Some(&json!([]))
        );
    }

    #[test]
    fn shared_flutter_settings_merge_is_recursive() {
        let merged = merge_shared_flutter_settings(
            json!({
                "terminal": {
                    "fontFamily": "JetBrains Mono",
                    "loginShell": null,
                    "futureOption": true
                },
                "general": {"starClicked": true}
            }),
            json!({"terminal": {"cursorShape": "bar"}, "editor": {"themeName": "Nord"}}),
        )
        .expect("settings merge should succeed");

        assert_eq!(
            merged.pointer("/terminal/fontFamily"),
            Some(&json!("JetBrains Mono"))
        );
        assert_eq!(merged.pointer("/terminal/cursorShape"), Some(&json!("bar")));
        assert_eq!(merged.pointer("/terminal/futureOption"), Some(&json!(true)));
        assert_eq!(merged.pointer("/general/starClicked"), Some(&json!(true)));
    }
}
