use std::path::{Path, PathBuf};

use serde_json::{Map, Value};

use super::{
    clean_managed_definitions, install_claude_hooks_into, object_field, write_json_object,
};

/// Installs the managed Claude hooks into the user's own `settings.json`.
///
/// That file is the only settings source every Claude Code session reads: CCS
/// overrides `CLAUDE_CONFIG_DIR` to `$CCS_DIR/instances/<account>`, whose
/// `settings.json` symlinks back here, and Claude reads no other file from a
/// config directory. Writing anywhere inside CCS instead is not an option -
/// CCS reconciles those paths on every launch and adopts a diverged copy back
/// into this same file.
///
/// Grok scans this file for Claude Code compatibility, so the managed command
/// carries its own `CLAUDECODE` guard (see `integration_hook_scripts`).
pub(super) fn install_claude_user_hooks(home: &Path, script: &Path) -> anyhow::Result<()> {
    let path = home.join(".claude/settings.json");
    let settings = read_jsonc_object(&path)?.unwrap_or_default();
    let mut updated = settings.clone();
    install_claude_hooks_into(&mut updated, script);
    // The file belongs to the user and this runs on every reconcile, so leave
    // it byte-identical when nothing changed rather than reformatting it.
    if updated == settings {
        return Ok(());
    }
    write_json_object(&path, &updated)
}

/// Removes the managed Claude hooks from the user's settings.json. Used when
/// the Claude toggle is off, and to clear what an older Alera left behind.
pub(super) fn cleanup_claude_user_hooks(home: &Path) -> anyhow::Result<()> {
    let mut errors = Vec::new();
    for path in claude_settings_cleanup_paths(home) {
        if let Err(error) = cleanup_managed_hooks_file(&path) {
            errors.push(format!("{}: {error}", path.display()));
        }
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(anyhow::anyhow!(errors.join("; ")))
    }
}

fn claude_settings_cleanup_paths(home: &Path) -> Vec<PathBuf> {
    // CCS instance settings.json symlinks here, so cleaning this one file also
    // clears every CCS account. `settings.local.json` is not a config-directory
    // settings source for Claude at all; it is cleaned only to drop leftovers.
    vec![
        home.join(".claude/settings.json"),
        home.join(".claude/settings.local.json"),
    ]
}

fn read_jsonc_object(path: &Path) -> anyhow::Result<Option<Map<String, Value>>> {
    let contents = match std::fs::read_to_string(path) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error.into()),
    };
    let parsed: Value = serde_json::from_str(&strip_jsonc_comments(&contents))
        .map_err(|error| anyhow::anyhow!("Could not parse {}: {error}", path.display()))?;
    Ok(parsed.as_object().cloned())
}

/// Strips Alera-managed hook definitions from a Claude- or Cursor-shaped JSON
/// file. User entries stay. Missing files are a no-op.
pub(super) fn cleanup_managed_hooks_file(path: &Path) -> anyhow::Result<()> {
    let contents = match std::fs::read_to_string(path) {
        Ok(contents) => contents,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error.into()),
    };
    let parsed: Value = serde_json::from_str(&strip_jsonc_comments(&contents))
        .map_err(|error| anyhow::anyhow!("Could not parse {}: {error}", path.display()))?;
    let Some(mut config) = parsed.as_object().cloned() else {
        return Ok(());
    };
    let mut changed = false;
    {
        let hooks = object_field(&mut config, "hooks");
        let mut kept = Map::new();
        for (event, value) in std::mem::take(hooks) {
            let Some(definitions) = value.as_array() else {
                kept.insert(event, value);
                continue;
            };
            let had = definitions.len();
            let cleaned = clean_managed_definitions(Some(value));
            if cleaned.len() != had {
                changed = true;
            }
            if !cleaned.is_empty() || had == 0 {
                kept.insert(event, Value::Array(cleaned));
            }
        }
        *hooks = kept;
    }
    if !changed {
        return Ok(());
    }
    if config
        .get("hooks")
        .and_then(Value::as_object)
        .is_some_and(Map::is_empty)
    {
        config.remove("hooks");
    }
    write_json_object(path, &config)
}

/// Drop `//` and `/* */` comments outside JSON strings so Claude JSONC
/// settings still parse. Comment text inside strings is left alone.
fn strip_jsonc_comments(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let mut chars = input.chars().peekable();
    let mut in_string = false;
    let mut escape = false;
    while let Some(c) = chars.next() {
        if in_string {
            out.push(c);
            if escape {
                escape = false;
            } else if c == '\\' {
                escape = true;
            } else if c == '"' {
                in_string = false;
            }
            continue;
        }
        if c == '"' {
            in_string = true;
            out.push(c);
            continue;
        }
        if c == '/' {
            match chars.peek() {
                Some('/') => {
                    chars.next();
                    for next in chars.by_ref() {
                        if next == '\n' {
                            out.push('\n');
                            break;
                        }
                    }
                }
                Some('*') => {
                    chars.next();
                    let mut prev = '\0';
                    for next in chars.by_ref() {
                        if prev == '*' && next == '/' {
                            break;
                        }
                        prev = next;
                    }
                }
                _ => out.push(c),
            }
            continue;
        }
        out.push(c);
    }
    out
}
