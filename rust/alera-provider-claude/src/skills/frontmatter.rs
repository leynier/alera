//! A `SKILL.md` frontmatter as Claude Code reads it (T3 Code's
//! `parseSkillFrontmatter`), including the repair of plain scalars that
//! contain `: `, which the CLI accepts but YAML rejects.

use super::paths::js_trim;
use alera_provider_protocol::{
    parse_skill_frontmatter_yaml, skill_frontmatter_block, skill_frontmatter_flag,
};
use serde_json::Value;

#[derive(Debug, Default, PartialEq, Eq)]
pub(crate) struct SkillMetadata {
    pub name: Option<String>,
    pub description: Option<String>,
    pub user_invocation_only: bool,
    pub user_invocable: bool,
}

#[derive(Debug, PartialEq, Eq)]
pub(crate) enum SkillFrontmatter {
    Missing,
    Malformed,
    Parsed(SkillMetadata),
}

impl SkillFrontmatter {
    pub fn metadata(&self) -> Option<&SkillMetadata> {
        match self {
            Self::Parsed(metadata) => Some(metadata),
            _ => None,
        }
    }
}

pub(crate) fn parse_frontmatter(contents: &str) -> SkillFrontmatter {
    let Some(block) = skill_frontmatter_block(contents) else {
        return SkillFrontmatter::Missing;
    };
    let parsed = match parse_skill_frontmatter_yaml(block) {
        Ok(value) => value,
        Err(_) => match parse_skill_frontmatter_yaml(&repair_colon_scalars(block)) {
            Ok(value) => value,
            Err(_) => return SkillFrontmatter::Malformed,
        },
    };
    // A YAML sequence is a JavaScript object too, so it parses without fields.
    if !parsed.is_object() && !parsed.is_array() {
        return SkillFrontmatter::Malformed;
    }
    let text = |key: &str| {
        parsed
            .get(key)
            .and_then(Value::as_str)
            .map(js_trim)
            .filter(|text| !text.is_empty())
            .map(str::to_owned)
    };
    SkillFrontmatter::Parsed(SkillMetadata {
        name: text("name"),
        description: text("description"),
        user_invocation_only: skill_frontmatter_flag(parsed.get("disable-model-invocation"), true)
            == Some(true),
        user_invocable: skill_frontmatter_flag(parsed.get("user-invocable"), true) != Some(false),
    })
}

/// Quotes each `key: value` line whose value holds `: `, as
/// `/^([\w-]+:[ \t]*)([^\r\n]*)/gm` does in T3 Code, leaving a trailing
/// ` # comment` and values that open YAML structure alone.
fn repair_colon_scalars(block: &str) -> String {
    let mut repaired = String::with_capacity(block.len());
    let mut line_start = 0;
    let mut index = 0;
    while index <= block.len() {
        let at_line_start = index == line_start;
        if at_line_start {
            if let Some((replacement, consumed)) = repair_line(&block[index..]) {
                repaired.push_str(&replacement);
                index += consumed;
                continue;
            }
        }
        let Some(character) = block[index..].chars().next() else {
            break;
        };
        repaired.push(character);
        index += character.len_utf8();
        if matches!(character, '\n' | '\r' | '\u{2028}' | '\u{2029}') {
            line_start = index;
        }
    }
    repaired
}

/// The rewritten `key: value` prefix of [line] and its byte length, or `None`
/// when the line does not open with a key or keeps its text.
fn repair_line(line: &str) -> Option<(String, usize)> {
    let key_length = line
        .find(|character: char| {
            !(character.is_ascii_alphanumeric() || matches!(character, '_' | '-'))
        })
        .unwrap_or(line.len());
    if key_length == 0 || !line[key_length..].starts_with(':') {
        return None;
    }
    let after_colon = key_length + 1;
    let prefix_length = after_colon
        + line[after_colon..]
            .find(|character: char| character != ' ' && character != '\t')
            .unwrap_or(line.len() - after_colon);
    let value_length = line[prefix_length..]
        .find(['\r', '\n'])
        .unwrap_or(line.len() - prefix_length);
    let value = &line[prefix_length..prefix_length + value_length];
    let scalar = &value[..comment_start(value)];
    if !has_colon_space(scalar) || opens_structure(scalar) {
        return None;
    }
    let quoted = serde_json::to_string(scalar).ok()?;
    Some((
        format!(
            "{}{quoted}{}",
            &line[..prefix_length],
            &value[scalar.len()..]
        ),
        prefix_length + value_length,
    ))
}

/// Where `value.split(/[ \t]+#/)[0]` ends: the blank run before the first
/// `#` that follows a blank.
fn comment_start(value: &str) -> usize {
    let bytes = value.as_bytes();
    for (index, byte) in bytes.iter().enumerate() {
        if *byte == b'#' && index > 0 && matches!(bytes[index - 1], b' ' | b'\t') {
            let mut start = index - 1;
            while start > 0 && matches!(bytes[start - 1], b' ' | b'\t') {
                start -= 1;
            }
            return start;
        }
    }
    value.len()
}

fn has_colon_space(scalar: &str) -> bool {
    scalar.contains(": ") || scalar.contains(":\t")
}

/// `/^(?:["'[\]{}|>&*!#%@`]|[-?:](?:[ \t]|$))/`.
fn opens_structure(scalar: &str) -> bool {
    let mut characters = scalar.chars();
    match characters.next() {
        Some(
            '"' | '\'' | '[' | ']' | '{' | '}' | '|' | '>' | '&' | '*' | '!' | '#' | '%' | '@'
            | '`',
        ) => true,
        Some('-' | '?' | ':') => matches!(characters.next(), None | Some(' ' | '\t')),
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn colon_values_are_quoted_and_comments_and_structure_are_kept() {
        assert_eq!(
            repair_colon_scalars(
                "name: x\ndescription: Run: now # note: here\ntools: [a: b]\r\nk: - a: b"
            ),
            "name: x\ndescription: \"Run: now\" # note: here\ntools: [a: b]\r\nk: - a: b"
        );
        assert_eq!(
            repair_colon_scalars("a: C:\\x#y: \"q\"\n  b: c: d"),
            "a: \"C:\\\\x#y: \\\"q\\\"\"\n  b: c: d"
        );
    }

    #[test]
    fn missing_malformed_and_parsed_frontmatter_are_told_apart() {
        assert_eq!(parse_frontmatter("# Title"), SkillFrontmatter::Missing);
        assert_eq!(
            parse_frontmatter("---\nplain\n---\n"),
            SkillFrontmatter::Malformed
        );
        assert_eq!(
            parse_frontmatter("---\n- item\n---\n"),
            SkillFrontmatter::Parsed(SkillMetadata {
                user_invocable: true,
                ..Default::default()
            })
        );
    }
}
