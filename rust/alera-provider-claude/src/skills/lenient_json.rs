//! Claude Code settings files are hand-edited and the CLI tolerates comments
//! and trailing commas in them. This mirrors T3 Code's `fromLenientJson`:
//! comments become a space, a comma before `}` or `]` is dropped, and string
//! literals are copied untouched, before a strict JSON parse.

use alera_provider_protocol::is_mention_space;
use serde_json::Value;

pub(crate) fn parse_lenient_json(input: &str) -> Option<Value> {
    serde_json::from_str(&drop_trailing_commas(&strip_comments(input))).ok()
}

/// The end of the string literal opening at [start], as
/// `"(?:[^"\\]|\\.)*"` matches it, or `None` when it is unterminated.
fn string_literal_end(text: &str, start: usize) -> Option<usize> {
    let mut characters = text[start + 1..].char_indices();
    while let Some((offset, character)) = characters.next() {
        match character {
            '"' => return Some(start + 1 + offset + 1),
            '\\' => match characters.next() {
                Some((_, '\n' | '\r' | '\u{2028}' | '\u{2029}')) | None => return None,
                Some(_) => {}
            },
            _ => {}
        }
    }
    None
}

fn strip_comments(input: &str) -> String {
    let mut output = String::with_capacity(input.len());
    let mut index = 0;
    while let Some(character) = input[index..].chars().next() {
        let rest = &input[index..];
        if character == '"' {
            if let Some(end) = string_literal_end(input, index) {
                output.push_str(&input[index..end]);
                index = end;
                continue;
            }
        } else if rest.starts_with("//") {
            index += rest.find('\n').unwrap_or(rest.len());
            output.push(' ');
            continue;
        } else if let Some(body) = rest.strip_prefix("/*") {
            if let Some(close) = body.find("*/") {
                index += close + 4;
                output.push(' ');
                continue;
            }
        }
        output.push(character);
        index += character.len_utf8();
    }
    output
}

fn drop_trailing_commas(input: &str) -> String {
    let mut output = String::with_capacity(input.len());
    let mut index = 0;
    while let Some(character) = input[index..].chars().next() {
        if character == '"' {
            if let Some(end) = string_literal_end(input, index) {
                output.push_str(&input[index..end]);
                index = end;
                continue;
            }
        } else if character == ',' {
            let after = input[index + 1..].trim_start_matches(is_mention_space);
            if after.starts_with('}') || after.starts_with(']') {
                index += 1;
                continue;
            }
        }
        output.push(character);
        index += character.len_utf8();
    }
    output
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn comments_and_trailing_commas_are_tolerated_outside_strings() {
        let source = "{\n // note\n \"url\": \"http://x/*y*/\", /* block\n */ \"list\": [1, 2, ],\n \"s\": \"a,}\\\" // b\",\n}";
        assert_eq!(
            parse_lenient_json(source),
            Some(json!({"url": "http://x/*y*/", "list": [1, 2], "s": "a,}\" // b"}))
        );
    }

    #[test]
    fn unparseable_text_is_none() {
        assert_eq!(parse_lenient_json("{ not json"), None);
        assert_eq!(parse_lenient_json("{\"a\": 1 /* open"), None);
    }
}
