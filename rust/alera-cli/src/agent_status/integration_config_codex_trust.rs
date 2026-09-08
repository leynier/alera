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
    format!(
        "sha256:{}",
        hex::encode(Sha256::digest(serialized.as_bytes()))
    )
}

pub(super) fn upsert_codex_hook_trust(
    state: &mut toml::map::Map<String, toml::Value>,
    hooks_path: &Path,
    entries: &[(&str, usize, String)],
) {
    let prefix = format!("{}:", hooks_path.display());
    for (label, index, command) in entries {
        let key = format!("{prefix}{label}:{index}:0");
        let mut entry = toml::map::Map::new();
        entry.insert("enabled".to_string(), toml::Value::Boolean(true));
        entry.insert(
            "trusted_hash".to_string(),
            toml::Value::String(codex_trusted_hash(label, command)),
        );
        state.insert(key, toml::Value::Table(entry));
    }
}

/// Drops Alera-owned Codex trust records and leftover runtime-home keys.
///
/// User trust entries whose event index still exists after Alera definitions
/// were stripped from `hooks.json` are left alone. Alera always appends, so
/// removing from the end does not shift those indices.
pub(super) fn remove_alera_codex_hook_trust(
    state: &mut toml::map::Map<String, toml::Value>,
    hooks_path: &Path,
    remaining_counts: Vec<(String, usize)>,
) {
    let prefixes = codex_hook_path_key_prefixes(hooks_path);
    let remaining: BTreeMap<String, usize> = remaining_counts.into_iter().collect();
    let stale = state
        .keys()
        .filter(|key| {
            if is_legacy_runtime_home_key(key) {
                return true;
            }
            let Some((label, index)) = parse_trust_key_suffix(key, &prefixes) else {
                return false;
            };
            remaining.get(&label).is_some_and(|count| index >= *count)
        })
        .cloned()
        .collect::<Vec<_>>();
    for key in stale {
        state.remove(&key);
    }
}

fn is_legacy_runtime_home_key(key: &str) -> bool {
    key.contains("agent-runtime-homes/codex") || key.contains("agent-runtime-homes\\codex")
}

fn parse_trust_key_suffix(key: &str, prefixes: &[String]) -> Option<(String, usize)> {
    let prefix = prefixes
        .iter()
        .find(|prefix| key.starts_with(&format!("{prefix}:")))?;
    let suffix = key.get(prefix.len() + 1..)?;
    let mut parts = suffix.rsplitn(3, ':');
    let _handler = parts.next()?;
    let index = parts.next()?.parse::<usize>().ok()?;
    let label = parts.next()?.to_string();
    Some((label, index))
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
    fn upserts_enabled_trust_records_for_alera_commands() {
        let hooks = PathBuf::from("/home/user/.codex/hooks.json");
        let mut state = toml::map::Map::new();
        upsert_codex_hook_trust(
            &mut state,
            &hooks,
            &[("session_start", 1, "alera-runtime-agent-hook.sh".into())],
        );

        let key = format!("{}:session_start:1:0", hooks.display());
        let entry = state.get(&key).and_then(toml::Value::as_table).unwrap();
        assert_eq!(
            entry.get("enabled").and_then(toml::Value::as_bool),
            Some(true)
        );
        assert_eq!(
            entry.get("trusted_hash").and_then(toml::Value::as_str),
            Some(codex_trusted_hash("session_start", "alera-runtime-agent-hook.sh").as_str())
        );
    }

    #[test]
    fn removes_alera_and_legacy_runtime_home_keys_and_keeps_user_trust() {
        let hooks = PathBuf::from("/home/user/.codex/hooks.json");
        let user_key = format!("{}:session_start:0:0", hooks.display());
        let alera_key = format!("{}:session_start:1:0", hooks.display());
        let leftover =
            "/tmp/alera-runtime/agent-runtime-homes/codex/home/hooks.json:stop:0:0".to_string();
        let mut state = toml::map::Map::new();
        for key in [&user_key, &alera_key, &leftover] {
            let mut entry = toml::map::Map::new();
            entry.insert("enabled".to_string(), toml::Value::Boolean(true));
            state.insert(key.clone(), toml::Value::Table(entry));
        }

        remove_alera_codex_hook_trust(&mut state, &hooks, vec![("session_start".into(), 1)]);

        assert!(state.contains_key(&user_key));
        assert!(!state.contains_key(&alera_key));
        assert!(!state.contains_key(&leftover));
    }
}
