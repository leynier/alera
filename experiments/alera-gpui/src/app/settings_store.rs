use std::fs;
use std::path::PathBuf;
use std::thread;

use async_channel::{Receiver, Sender};

use super::settings_state::SettingsState;

#[derive(Clone)]
pub(super) struct SettingsStore {
    updates: Sender<SettingsState>,
}

impl SettingsStore {
    pub fn start() -> (Self, SettingsState) {
        let path = settings_path();
        let initial = load_from_path(&path).unwrap_or_default();
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
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("Alera")
        .join("gpui-settings.json")
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
    use super::{load_from_path, write_to_path};
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
}
