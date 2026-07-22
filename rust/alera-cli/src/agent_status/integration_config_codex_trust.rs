use std::collections::BTreeMap;
use std::path::Path;

use serde_json::json;
use sha2::{Digest, Sha256};

pub(super) fn codex_trusted_hash(event_label: &str, command: &str) -> String {
    let identity = BTreeMap::from([
        ("event_name", json!(event_label)),
        (
            "hooks",
            json!([{ "async": false, "command": command, "timeout": 600, "type": "command" }]),
        ),
    ]);
    let serialized = serde_json::to_string(&identity).expect("serializable trust identity");
    format!("sha256:{:x}", Sha256::digest(serialized.as_bytes()))
}

pub(super) fn remap_codex_source_hook_trust(
    state: &mut toml::map::Map<String, toml::Value>,
    source_hooks_path: &Path,
    runtime_hooks_path: &Path,
) {
    let source_prefixes = codex_hook_path_key_prefixes(source_hooks_path);
    if source_prefixes.is_empty() {
        return;
    }
    let runtime_prefix = format!("{}:", runtime_hooks_path.display());
    let mut remaps = Vec::new();
    for key in state.keys() {
        for source_prefix in &source_prefixes {
            let old_prefix = format!("{source_prefix}:");
            if let Some(suffix) = key.strip_prefix(&old_prefix) {
                remaps.push((key.clone(), format!("{runtime_prefix}{suffix}")));
                break;
            }
        }
    }
    for (old_key, new_key) in remaps {
        if let Some(entry) = state.remove(&old_key) {
            state.insert(new_key, entry);
        }
    }
}

fn codex_hook_path_key_prefixes(path: &Path) -> Vec<String> {
    let mut prefixes = Vec::new();
    let display = path.display().to_string();
    if !display.is_empty() {
        prefixes.push(display.clone());
    }
    if let Ok(canonical) = std::fs::canonicalize(path) {
        let canonical_display = canonical.display().to_string();
        if !canonical_display.is_empty()
            && !prefixes.iter().any(|value| value == &canonical_display)
        {
            prefixes.push(canonical_display);
        }
    }
    prefixes
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn remaps_trusted_source_hook_records_to_runtime_hooks_path() {
        let source_hooks = PathBuf::from("/home/user/.codex/hooks.json");
        let runtime_hooks =
            PathBuf::from("/tmp/alera-runtime/agent-runtime-homes/codex/home/hooks.json");
        let source_key = format!("{}:session_start:0:0", source_hooks.display());
        let runtime_key = format!("{}:session_start:0:0", runtime_hooks.display());
        let mut state = toml::map::Map::new();
        let mut entry = toml::map::Map::new();
        entry.insert("enabled".to_string(), toml::Value::Boolean(true));
        entry.insert(
            "trusted_hash".to_string(),
            toml::Value::String("sha256:source-trusted".to_string()),
        );
        state.insert(source_key.clone(), toml::Value::Table(entry));

        remap_codex_source_hook_trust(&mut state, &source_hooks, &runtime_hooks);

        assert!(!state.contains_key(&source_key));
        let remapped = state
            .get(&runtime_key)
            .and_then(toml::Value::as_table)
            .expect("remapped trust entry");
        assert_eq!(
            remapped.get("enabled").and_then(toml::Value::as_bool),
            Some(true)
        );
        assert_eq!(
            remapped.get("trusted_hash").and_then(toml::Value::as_str),
            Some("sha256:source-trusted")
        );
    }

    #[test]
    fn leaves_untrusted_source_hooks_without_runtime_trust_records() {
        let source_hooks = PathBuf::from("/home/user/.codex/hooks.json");
        let runtime_hooks =
            PathBuf::from("/tmp/alera-runtime/agent-runtime-homes/codex/home/hooks.json");
        let mut state = toml::map::Map::new();
        let unrelated_key = "/other/hooks.json:stop:0:0".to_string();
        let mut unrelated = toml::map::Map::new();
        unrelated.insert("enabled".to_string(), toml::Value::Boolean(false));
        unrelated.insert(
            "trusted_hash".to_string(),
            toml::Value::String("sha256:other".to_string()),
        );
        state.insert(unrelated_key.clone(), toml::Value::Table(unrelated));

        remap_codex_source_hook_trust(&mut state, &source_hooks, &runtime_hooks);

        assert_eq!(state.len(), 1);
        assert!(state.contains_key(&unrelated_key));
        assert!(!state
            .keys()
            .any(|key| { key.starts_with(&format!("{}:", runtime_hooks.display())) }));
    }
}
