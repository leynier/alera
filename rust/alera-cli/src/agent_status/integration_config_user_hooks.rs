use std::path::{Path, PathBuf};

use serde_json::{Map, Value};

use super::{clean_managed_definitions, object_field, write_json_object};

/// Older Alera versions wrote Claude hooks into the user's settings.json.
/// Grok scans that file by default, so leftover Alera commands still fire as
/// `/hook/claude` for a Grok turn. Strip only Alera-managed definitions.
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
    // Grok scans ~/.claude/settings.json by default. CCS instance
    // settings.json usually symlinks there, so leftover cleanup must not
    // walk CCS files: that would strip (or write through to) the user file
    // and would also undo instance settings.local.json while Claude is on.
    vec![
        home.join(".claude/settings.json"),
        home.join(".claude/settings.local.json"),
    ]
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
