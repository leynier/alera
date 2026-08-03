//! Safe progressive Markdown rendering for persisted Codex timeline cells.
//!
//! This is a Rust port of the default remend 1.3.1 handler pipeline at
//! `5d9c213830dfe84bcbb8edfbf002ccc0f168741a`. The runtime deliberately uses
//! text-only links while a URL is incomplete. That keeps a streaming snapshot
//! from ever handing `streamdown:incomplete-link` to a Flutter link handler.

use regex::Regex;

pub(super) fn normalize_markdown_newlines(text: &str) -> String {
    text.replace("\r\n", "\n").replace('\r', "\n")
}

pub(super) fn render_markdown(raw: &str) -> String {
    let mut result = normalize_markdown_newlines(raw);
    if result.ends_with(' ') && !result.ends_with("  ") {
        result.pop();
    }
    result = single_tilde(&result);
    result = comparison_operators(&result);
    result = incomplete_html_tag(&result);
    result = incomplete_setext_heading(&result);
    result = incomplete_links_text_only(&result);
    result = incomplete_emphasis(&result);
    result = incomplete_inline_code(&result);
    result = incomplete_strikethrough(&result);
    incomplete_block_katex(&result)
}

fn is_word(character: char) -> bool {
    character == '_' || character.is_alphanumeric()
}

fn is_escaped(text: &str, byte_index: usize) -> bool {
    let bytes = text.as_bytes();
    let mut index = byte_index;
    let mut slashes = 0;
    while index > 0 && bytes[index - 1] == b'\\' {
        slashes += 1;
        index -= 1;
    }
    slashes % 2 == 1
}

fn is_in_code(text: &str, byte_index: usize) -> bool {
    let mut fenced = false;
    let mut inline = false;
    let mut index = 0;
    while index < byte_index {
        let remaining = &text[index..];
        if remaining.starts_with("```") && !is_escaped(text, index) {
            fenced = !fenced;
            index += 3;
            continue;
        }
        if !fenced && text[index..].starts_with('`') && !is_escaped(text, index) {
            inline = !inline;
        }
        let width = text[index..]
            .chars()
            .next()
            .map(char::len_utf8)
            .unwrap_or(1);
        index += width;
    }
    fenced || inline
}

fn single_tilde(text: &str) -> String {
    let chars: Vec<char> = text.chars().collect();
    let mut result = String::with_capacity(text.len() + 4);
    let mut byte_index = 0;
    for (index, character) in chars.iter().copied().enumerate() {
        if character == '~'
            && (index == 0 || chars[index - 1] != '~')
            && (index + 1 == chars.len() || chars[index + 1] != '~')
            && index > 0
            && index + 1 < chars.len()
            && is_word(chars[index - 1])
            && is_word(chars[index + 1])
            && !is_escaped(text, byte_index)
            && !is_in_code(text, byte_index)
        {
            result.push('\\');
        }
        result.push(character);
        byte_index += character.len_utf8();
    }
    result
}

fn comparison_operators(text: &str) -> String {
    let pattern = Regex::new(r"(?m)^(\s*(?:[-*+]|\d+[.)]) +)>(=?\s*[$]?\d)").unwrap();
    pattern
        .replace_all(text, |captures: &regex::Captures<'_>| {
            if is_in_code(
                text,
                captures.get(0).map(|value| value.start()).unwrap_or(0),
            ) {
                captures[0].to_string()
            } else {
                format!("{}\\>{}", &captures[1], &captures[2])
            }
        })
        .into_owned()
}

fn incomplete_html_tag(text: &str) -> String {
    let pattern = Regex::new(r"<[a-zA-Z/][^>]*$").unwrap();
    let Some(matched) = pattern.find(text) else {
        return text.to_string();
    };
    if is_in_code(text, matched.start()) {
        return text.to_string();
    }
    text[..matched.start()].trim_end().to_string()
}

fn incomplete_setext_heading(text: &str) -> String {
    let Some((previous, last)) = text.rsplit_once('\n') else {
        return text.to_string();
    };
    let trimmed = last.trim();
    if previous
        .rsplit('\n')
        .next()
        .is_some_and(|line| !line.trim().is_empty())
        && (trimmed == "-" || trimmed == "--" || trimmed == "=" || trimmed == "==")
        && !last.ends_with(char::is_whitespace)
    {
        return format!("{text}\u{200b}");
    }
    text.to_string()
}

fn matching_open_bracket(text: &str, close: usize) -> Option<usize> {
    let chars: Vec<(usize, char)> = text.char_indices().collect();
    let close_position = chars
        .iter()
        .position(|(index, character)| *index == close && *character == ']')?;
    let mut depth = 1;
    for (_, character) in chars[..close_position].iter().rev() {
        if *character == ']' {
            depth += 1;
        } else if *character == '[' {
            depth -= 1;
            if depth == 0 {
                return Some(
                    chars[..close_position]
                        .iter()
                        .rev()
                        .find(|(_, value)| *value == '[')
                        .map(|(index, _)| *index)
                        .unwrap_or(close),
                );
            }
        }
    }
    None
}

fn incomplete_links_text_only(text: &str) -> String {
    let Some(paren) = text.rfind("](") else {
        return incomplete_link_text(text);
    };
    if text[paren + 2..].contains(')') || is_in_code(text, paren) {
        return incomplete_link_text(text);
    }
    let Some(open) = matching_open_bracket(text, paren) else {
        return incomplete_link_text(text);
    };
    let start = if open > 0 && text[..open].ends_with('!') {
        open - 1
    } else {
        open
    };
    if is_in_code(text, start) {
        return text.to_string();
    }
    if start < open {
        return text[..start].to_string();
    }
    format!("{}{}", &text[..start], &text[open + 1..paren])
}

fn incomplete_link_text(text: &str) -> String {
    let Some(open) = text.rfind('[') else {
        return text.to_string();
    };
    if is_in_code(text, open) || text[open + 1..].contains(']') {
        return text.to_string();
    }
    if open > 0 && text[..open].ends_with('!') {
        text[..open - 1].to_string()
    } else {
        format!("{}{}", &text[..open], &text[open + 1..])
    }
}

fn meaningful(content: &str) -> bool {
    content
        .chars()
        .any(|character| !character.is_whitespace() && !"_*~`".contains(character))
}

fn unmatched_pairs(text: &str, marker: &str) -> usize {
    let mut count = 0;
    let mut index = 0;
    while let Some(offset) = text[index..].find(marker) {
        let byte_index = index + offset;
        if !is_escaped(text, byte_index) && !is_in_code(text, byte_index) {
            count += 1;
        }
        index = byte_index + marker.len();
        if index >= text.len() {
            break;
        }
    }
    count
}

fn incomplete_emphasis(text: &str) -> String {
    let triple = Regex::new(r"(\*\*\*)([^*]*?)$").unwrap();
    if let Some(captures) = triple.captures(text) {
        let marker = captures.get(1).unwrap();
        if !is_in_code(text, marker.start())
            && meaningful(captures.get(2).map(|m| m.as_str()).unwrap_or_default())
            && unmatched_pairs(text, "***") % 2 == 1
        {
            return format!("{text}***");
        }
    }
    let bold = Regex::new(r"(\*\*)([^*]*\*?)$").unwrap();
    if let Some(captures) = bold.captures(text) {
        let marker = captures.get(1).unwrap();
        let content = captures.get(2).map(|m| m.as_str()).unwrap_or_default();
        if !is_in_code(text, marker.start())
            && meaningful(content)
            && unmatched_pairs(text, "**") % 2 == 1
        {
            return if content.ends_with('*') {
                format!("{text}*")
            } else {
                format!("{text}**")
            };
        }
    }
    let double_underscore = Regex::new(r"(__)([^_]*?)$|(__)([^_]+)_$").unwrap();
    if let Some(captures) = double_underscore.captures(text) {
        let marker = captures.get(1).or_else(|| captures.get(3)).unwrap();
        let content = captures
            .get(2)
            .or_else(|| captures.get(4))
            .map(|m| m.as_str())
            .unwrap_or_default();
        if !is_in_code(text, marker.start())
            && meaningful(content)
            && unmatched_pairs(text, "__") % 2 == 1
        {
            return if captures.get(3).is_some() {
                format!("{text}_")
            } else {
                format!("{text}__")
            };
        }
    }
    incomplete_single_marker(text, '*', "*")
        .or_else(|| incomplete_single_marker(text, '_', "_"))
        .unwrap_or_else(|| text.to_string())
}

fn incomplete_single_marker(text: &str, marker: char, token: &str) -> Option<String> {
    let chars: Vec<(usize, char)> = text.char_indices().collect();
    let (byte_index, _) = chars
        .iter()
        .rev()
        .find(|(_, character)| *character == marker)?;
    if is_in_code(text, *byte_index) || is_escaped(text, *byte_index) {
        return None;
    }
    let next = text[*byte_index + marker.len_utf8()..].to_string();
    if !meaningful(&next) || unmatched_pairs(text, token).is_multiple_of(2) {
        return None;
    }
    let previous = chars
        .iter()
        .rev()
        .find(|(index, _)| *index < *byte_index)
        .map(|(_, character)| *character);
    if previous.is_some_and(is_word) && next.chars().next().is_some_and(is_word) {
        return None;
    }
    Some(format!("{text}{token}"))
}

fn incomplete_inline_code(text: &str) -> String {
    let mut count = 0;
    for (index, character) in text.char_indices() {
        if character == '`' && !is_triple_backtick(text, index) && !is_escaped(text, index) {
            count += 1;
        }
    }
    if count % 2 == 1 && count > 0 {
        let opening = text.find('`').unwrap_or(text.len());
        let content = &text[opening + 1..];
        if content.is_empty() || content.chars().all(|character| character.is_whitespace()) {
            return text.to_string();
        }
        format!("{text}`")
    } else {
        text.to_string()
    }
}

fn is_triple_backtick(text: &str, index: usize) -> bool {
    let bytes = text.as_bytes();
    (index >= 2 && bytes[index - 2..=index] == *b"```")
        || (index > 0 && index + 1 < bytes.len() && bytes[index - 1..=index + 1] == *b"```")
        || bytes[index..].starts_with(b"```")
}

fn incomplete_strikethrough(text: &str) -> String {
    let pattern = Regex::new(r"(~~)([^~]*?)$").unwrap();
    if let Some(captures) = pattern.captures(text) {
        let marker = captures.get(1).unwrap();
        let content = captures.get(2).map(|m| m.as_str()).unwrap_or_default();
        if !is_in_code(text, marker.start())
            && meaningful(content)
            && unmatched_pairs(text, "~~") % 2 == 1
        {
            return format!("{text}~~");
        }
    }
    let half = Regex::new(r"(~~)([^~]+)~$").unwrap();
    if let Some(captures) = half.captures(text) {
        let marker = captures.get(1).unwrap();
        if !is_in_code(text, marker.start()) && unmatched_pairs(text, "~~") % 2 == 1 {
            return format!("{text}~");
        }
    }
    text.to_string()
}

fn incomplete_block_katex(text: &str) -> String {
    let mut pairs = 0;
    let mut inline = false;
    let mut index = 0;
    while index + 1 < text.len() {
        if text[index..].starts_with("```") {
            index += 3;
            while index + 2 < text.len() && !text[index..].starts_with("```") {
                index += text[index..]
                    .chars()
                    .next()
                    .map(char::len_utf8)
                    .unwrap_or(1);
            }
            index = (index + 3).min(text.len());
            continue;
        }
        if text[index..].starts_with('`') {
            inline = !inline;
            index += 1;
            continue;
        }
        if !inline && text[index..].starts_with("$$") {
            pairs += 1;
            index += 2;
        } else {
            index += text[index..]
                .chars()
                .next()
                .map(char::len_utf8)
                .unwrap_or(1);
        }
    }
    if pairs % 2 == 0 {
        return text.to_string();
    }
    if text.ends_with('$') && !text.ends_with("$$") {
        format!("{text}$")
    } else if text.contains('\n') && !text.ends_with('\n') {
        format!("{text}\n$$")
    } else {
        format!("{text}$$")
    }
}

#[cfg(test)]
mod tests {
    use super::render_markdown;

    #[test]
    fn normalizes_newlines_and_trailing_stream_space() {
        assert_eq!(render_markdown("one\r\ntwo\r "), "one\ntwo\n");
    }

    #[test]
    fn completes_default_remend_handlers() {
        assert_eq!(render_markdown("**bold"), "**bold**");
        assert_eq!(render_markdown("***bold italic"), "***bold italic***");
        assert_eq!(render_markdown("_italic"), "_italic_");
        assert_eq!(render_markdown("__italic"), "__italic__");
        assert_eq!(render_markdown("`code"), "`code`");
        assert_eq!(render_markdown("~~removed"), "~~removed~~");
        assert_eq!(render_markdown("$$x"), "$$x$$");
    }

    #[test]
    fn protects_streaming_links_and_images_without_special_urls() {
        assert_eq!(render_markdown("[link](https://example"), "link");
        assert_eq!(render_markdown("![image](https://example"), "");
        assert!(!render_markdown("[link](https://example").contains("streamdown:"));
    }

    #[test]
    fn protects_code_and_single_tilde_content() {
        assert_eq!(render_markdown("`20~25"), "`20~25`");
        assert_eq!(render_markdown("20~25"), "20\\~25");
        assert_eq!(render_markdown("```\n**raw\n```"), "```\n**raw\n```");
    }

    #[test]
    fn handles_comparison_html_and_setext_streams() {
        assert_eq!(render_markdown("- > 25"), "- \\> 25");
        assert_eq!(render_markdown("hello <custom"), "hello");
        assert_eq!(render_markdown("Heading\n--"), "Heading\n--\u{200b}");
    }
}
