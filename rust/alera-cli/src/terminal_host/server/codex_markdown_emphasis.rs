use regex::Regex;

use super::codex_markdown_scanner::{
    count_unescaped_outside_code, is_directly_escaped, is_horizontal_rule, is_in_code,
    is_within_html_tag, is_within_link_url, is_within_math, is_word_char, meaningful,
    only_markers_or_whitespace,
};

pub(super) fn complete_bold_italic(text: &str) -> String {
    if Regex::new(r"^\*{4,}$").unwrap().is_match(text) {
        return text.to_string();
    }
    let pattern = Regex::new(r"(\*\*\*)([^*]*?)$").unwrap();
    let Some(captures) = pattern.captures(text) else {
        return text.to_string();
    };
    let marker = captures.get(1).unwrap();
    let content = captures.get(2).map_or("", |value| value.as_str());
    if content.is_empty()
        || only_markers_or_whitespace(content)
        || is_in_code(text, marker.start())
        || is_horizontal_rule(text, marker.start(), '*')
    {
        return text.to_string();
    }
    if count_triple_asterisks(text) % 2 == 1 {
        if count_double_asterisks(text).is_multiple_of(2)
            && count_single_asterisks(text).is_multiple_of(2)
        {
            return text.to_string();
        }
        return format!("{text}***");
    }
    text.to_string()
}

pub(super) fn complete_bold(text: &str) -> String {
    let pattern = Regex::new(r"(\*\*)([^*]*\*?)$").unwrap();
    let Some(captures) = pattern.captures(text) else {
        return text.to_string();
    };
    let marker = captures.get(1).unwrap();
    let content = captures.get(2).map_or("", |value| value.as_str());
    if content.is_empty()
        || only_markers_or_whitespace(content)
        || is_in_code(text, marker.start())
        || is_horizontal_rule(text, marker.start(), '*')
        || (line_prefix_is_list(text, marker.start()) && content.contains('\n'))
    {
        return text.to_string();
    }
    if count_double_asterisks(text) % 2 == 1 {
        return if content.ends_with('*') {
            format!("{text}*")
        } else {
            format!("{text}**")
        };
    }
    text.to_string()
}

pub(super) fn complete_double_underscore(text: &str) -> String {
    let pattern = Regex::new(r"(__)([^_]*?)$").unwrap();
    if let Some(captures) = pattern.captures(text) {
        let marker = captures.get(1).unwrap();
        let content = captures.get(2).map_or("", |value| value.as_str());
        if !content.is_empty()
            && !only_markers_or_whitespace(content)
            && !is_in_code(text, marker.start())
            && count_double_underscores(text) % 2 == 1
        {
            return format!("{text}__");
        }
    }
    let half = Regex::new(r"(__)([^_]+)_$").unwrap();
    if let Some(captures) = half.captures(text) {
        let marker = captures.get(1).unwrap();
        if !is_in_code(text, marker.start()) && count_double_underscores(text) % 2 == 1 {
            return format!("{text}_");
        }
    }
    text.to_string()
}

pub(super) fn complete_single_asterisk(text: &str) -> String {
    let pattern = Regex::new(r"(\*)([^*]*?)$").unwrap();
    if pattern.captures(text).is_none() {
        return text.to_string();
    }
    let Some(index) = first_single_asterisk(text) else {
        return text.to_string();
    };
    let content = &text[index + 1..];
    if content.is_empty()
        || only_markers_or_whitespace(content)
        || is_in_code(text, index)
        || is_within_math(text, index)
    {
        return text.to_string();
    }
    if count_single_asterisks(text) % 2 == 1 {
        format!("{text}*")
    } else {
        text.to_string()
    }
}

pub(super) fn complete_single_underscore(text: &str) -> String {
    let pattern = Regex::new(r"(_)([^_]*?)$").unwrap();
    if pattern.captures(text).is_none() {
        return text.to_string();
    }
    let Some(index) = first_single_underscore(text) else {
        return text.to_string();
    };
    let content = &text[index + 1..];
    if content.is_empty()
        || only_markers_or_whitespace(content)
        || is_in_code(text, index)
        || is_within_math(text, index)
    {
        return text.to_string();
    }
    if count_single_underscores(text) % 2 != 1 {
        return text.to_string();
    }
    if let Some(without) = text.strip_suffix("**") {
        if count_double_asterisks(without) % 2 == 1
            && text.find("**").is_some_and(|bold| bold < index)
        {
            return format!("{without}_**");
        }
    }
    let mut end = text.len();
    while end > 0 && text[..end].ends_with('\n') {
        end -= 1;
    }
    format!("{}_{}", &text[..end], &text[end..])
}

fn line_prefix_is_list(text: &str, marker: usize) -> bool {
    let line = text[..marker]
        .rsplit_once('\n')
        .map_or(text, |(_, line)| line);
    let trimmed = line.trim_start();
    trimmed.starts_with("- ") || trimmed.starts_with("* ") || trimmed.starts_with("+ ")
}

fn first_single_asterisk(text: &str) -> Option<usize> {
    for (index, character) in text.char_indices() {
        if character != '*'
            || is_directly_escaped(text, index)
            || is_in_code(text, index)
            || is_within_math(text, index)
            || text[index + 1..].starts_with('*')
            || (index > 0 && text[..index].ends_with('*'))
        {
            continue;
        }
        let previous = text[..index].chars().next_back();
        let next = text[index + 1..].chars().next();
        if previous.is_some_and(is_word_char) && next.is_some_and(is_word_char) {
            continue;
        }
        if previous.is_none_or(char::is_whitespace) && next.is_none_or(char::is_whitespace) {
            continue;
        }
        return Some(index);
    }
    None
}

fn first_single_underscore(text: &str) -> Option<usize> {
    for (index, character) in text.char_indices() {
        if character != '_'
            || is_directly_escaped(text, index)
            || is_in_code(text, index)
            || is_within_math(text, index)
            || is_within_link_url(text, index)
            || is_within_html_tag(text, index)
            || text[index + 1..].starts_with('_')
            || (index > 0 && text[..index].ends_with('_'))
        {
            continue;
        }
        let previous = text[..index].chars().next_back();
        let next = text[index + 1..].chars().next();
        if previous.is_some_and(is_word_char) && next.is_some_and(is_word_char) {
            continue;
        }
        return Some(index);
    }
    None
}

fn count_single_asterisks(text: &str) -> usize {
    let mut count = 0;
    for (index, character) in text.char_indices() {
        if character != '*'
            || is_directly_escaped(text, index)
            || is_in_code(text, index)
            || is_within_math(text, index)
        {
            continue;
        }
        let previous = text[..index].chars().next_back();
        let next = text[index + 1..].chars().next();
        if previous == Some('*') || next == Some('*') {
            if previous != Some('*') && next == Some('*') && text[index + 2..].starts_with('*') {
                count += 1;
            }
            continue;
        }
        if previous.is_some_and(is_word_char) && next.is_some_and(is_word_char) {
            continue;
        }
        if previous.is_none_or(char::is_whitespace) && next.is_none_or(char::is_whitespace) {
            continue;
        }
        count += 1;
    }
    count
}

fn count_single_underscores(text: &str) -> usize {
    text.char_indices()
        .filter(|(index, character)| {
            *character == '_'
                && !is_directly_escaped(text, *index)
                && !is_in_code(text, *index)
                && !is_within_math(text, *index)
                && !is_within_link_url(text, *index)
                && !is_within_html_tag(text, *index)
                && !text[*index + 1..].starts_with('_')
                && !text[..*index].ends_with('_')
                && !(text[..*index].chars().next_back().is_some_and(is_word_char)
                    && text[*index + 1..].chars().next().is_some_and(is_word_char))
        })
        .count()
}

fn count_double_asterisks(text: &str) -> usize {
    count_unescaped_outside_code(text, "**")
}

fn count_double_underscores(text: &str) -> usize {
    count_unescaped_outside_code(text, "__")
}

fn count_triple_asterisks(text: &str) -> usize {
    let mut count = 0;
    let mut run = 0;
    for (index, character) in text.char_indices() {
        if character == '*' && !is_in_code(text, index) {
            run += 1;
        } else {
            count += run / 3;
            run = 0;
        }
    }
    count + run / 3
}

pub(super) fn complete_strikethrough(text: &str) -> String {
    let pattern = Regex::new(r"(~~)([^~]*?)$").unwrap();
    if let Some(captures) = pattern.captures(text) {
        let marker = captures.get(1).unwrap();
        let content = captures.get(2).map_or("", |value| value.as_str());
        if !content.is_empty()
            && meaningful(content)
            && !is_in_code(text, marker.start())
            && count_unescaped_outside_code(text, "~~") % 2 == 1
        {
            return format!("{text}~~");
        }
    }
    let half = Regex::new(r"(~~)([^~]+)~$").unwrap();
    if let Some(captures) = half.captures(text) {
        let marker = captures.get(1).unwrap();
        if !is_in_code(text, marker.start()) && count_unescaped_outside_code(text, "~~") % 2 == 1 {
            return format!("{text}~");
        }
    }
    text.to_string()
}
