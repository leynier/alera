//! The YAML frontmatter of an Agent Skills `SKILL.md`, shared by the adapters
//! that scan skill folders themselves (Claude Code, Cursor, Antigravity).
//! Values come back as JSON so each adapter reads the keys its CLI honors.

use serde_json::{Map, Number, Value};
use yaml_rust2::{Yaml, YamlLoader};

/// The block between a leading `---` line and the next `---` line, as
/// `^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)` finds it, or `None` when the
/// file does not open with one.
pub fn skill_frontmatter_block(contents: &str) -> Option<&str> {
    let body = contents
        .strip_prefix("---\n")
        .or_else(|| contents.strip_prefix("---\r\n"))?;
    let mut search = 0;
    while let Some(offset) = body[search..].find("\n---") {
        let newline = search + offset;
        let after = &body[newline + 4..];
        if after.is_empty() || after.starts_with('\n') || after.starts_with("\r\n") {
            let block = &body[..newline];
            return Some(block.strip_suffix('\r').unwrap_or(block));
        }
        search = newline + 1;
    }
    None
}

/// The first YAML document of [source] as JSON, `Null` for an empty one,
/// or `Err` when it does not parse.
pub fn parse_skill_frontmatter_yaml(source: &str) -> Result<Value, String> {
    let documents = YamlLoader::load_from_str(source).map_err(|error| error.to_string())?;
    Ok(documents
        .into_iter()
        .next()
        .map_or(Value::Null, yaml_to_json))
}

fn yaml_to_json(yaml: Yaml) -> Value {
    match yaml {
        Yaml::String(text) => Value::String(text),
        Yaml::Integer(number) => Value::Number(number.into()),
        Yaml::Real(text) => text
            .parse::<f64>()
            .ok()
            .and_then(Number::from_f64)
            .map_or(Value::String(text), Value::Number),
        Yaml::Boolean(flag) => Value::Bool(flag),
        Yaml::Array(items) => Value::Array(items.into_iter().map(yaml_to_json).collect()),
        Yaml::Hash(entries) => {
            let mut map = Map::new();
            for (key, value) in entries {
                let key = match key {
                    Yaml::String(text) | Yaml::Real(text) => text,
                    Yaml::Integer(number) => number.to_string(),
                    Yaml::Boolean(flag) => flag.to_string(),
                    _ => continue,
                };
                map.insert(key, yaml_to_json(value));
            }
            Value::Object(map)
        }
        Yaml::Alias(_) | Yaml::Null | Yaml::BadValue => Value::Null,
    }
}

/// A frontmatter flag, accepting the YAML 1.1 spellings the CLIs accept
/// (`yes`, `on`, `1`) that a YAML 1.2 parser leaves as text or numbers.
/// [single_letters] also accepts `y` and `n`, as Claude Code does.
pub fn skill_frontmatter_flag(value: Option<&Value>, single_letters: bool) -> Option<bool> {
    match value? {
        Value::Bool(flag) => Some(*flag),
        Value::Number(number) => match number.as_f64() {
            Some(1.0) => Some(true),
            Some(0.0) => Some(false),
            _ => None,
        },
        Value::String(text) => match text.trim().to_lowercase().as_str() {
            "true" | "yes" | "on" => Some(true),
            "false" | "no" | "off" => Some(false),
            "y" if single_letters => Some(true),
            "n" if single_letters => Some(false),
            _ => None,
        },
        _ => None,
    }
}

/// A trimmed, non-empty string field of a frontmatter map.
pub fn skill_frontmatter_text(map: &Value, key: &str) -> Option<String> {
    map.get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|text| !text.is_empty())
        .map(str::to_owned)
}
