use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{LazyLock, Mutex};

use serde::de::DeserializeOwned;
use serde_json::Value;

static SETTINGS_WRITE_LOCK: LazyLock<Mutex<()>> = LazyLock::new(|| Mutex::new(()));

pub fn load_subset<T>() -> T
where
    T: DeserializeOwned + Default,
{
    load_subset_from_path(&settings_path())
}

pub fn persist_fields(
    fields: impl IntoIterator<Item = (&'static str, Value)>,
) -> Result<(), String> {
    persist_fields_to_path(&settings_path(), fields)
}

fn settings_path() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("Alera")
        .join("gpui-settings.json")
}

fn load_subset_from_path<T>(path: &Path) -> T
where
    T: DeserializeOwned + Default,
{
    fs::read(path)
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or_default()
}

fn persist_fields_to_path(
    path: &Path,
    fields: impl IntoIterator<Item = (&'static str, Value)>,
) -> Result<(), String> {
    let _guard = SETTINGS_WRITE_LOCK
        .lock()
        .map_err(|_| "Settings write lock is poisoned.".to_string())?;
    let mut object = fs::read(path)
        .ok()
        .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok())
        .and_then(|value| value.as_object().cloned())
        .unwrap_or_default();
    object
        .entry("settings_schema_version".to_string())
        .or_insert_with(|| Value::from(1));
    for (key, value) in fields {
        object.insert(key.to_string(), value);
    }
    let parent = path
        .parent()
        .ok_or_else(|| "Settings path has no parent.".to_string())?;
    fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    let bytes =
        serde_json::to_vec_pretty(&Value::Object(object)).map_err(|error| error.to_string())?;
    fs::write(path, bytes).map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use serde::Deserialize;
    use serde_json::json;

    use super::{load_subset_from_path, persist_fields_to_path};

    #[derive(Debug, Default, Deserialize, PartialEq)]
    #[serde(default)]
    struct Subset {
        terminal_font_size: f64,
        terminal_cursor_blink: bool,
    }

    #[test]
    fn updates_preserve_fields_owned_by_other_settings_sections() {
        let path = std::env::temp_dir().join(format!(
            "alera-freya-settings-{}-{}.json",
            std::process::id(),
            std::thread::current().name().unwrap_or("thread")
        ));
        std::fs::write(
            &path,
            br#"{"editor_theme":"Nord","terminal_font_size":13.0}"#,
        )
        .expect("seed settings");
        persist_fields_to_path(
            &path,
            [
                ("terminal_font_size", json!(15.0)),
                ("terminal_cursor_blink", json!(true)),
            ],
        )
        .expect("persist terminal fields");
        let raw: serde_json::Value =
            serde_json::from_slice(&std::fs::read(&path).expect("read settings"))
                .expect("decode settings");
        assert_eq!(raw["editor_theme"], "Nord");
        assert_eq!(
            load_subset_from_path::<Subset>(&path),
            Subset {
                terminal_font_size: 15.0,
                terminal_cursor_blink: true,
            }
        );
        let _ = std::fs::remove_file(path);
    }
}
