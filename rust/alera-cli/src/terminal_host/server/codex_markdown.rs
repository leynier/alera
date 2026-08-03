//! Safe progressive Markdown rendering for persisted Codex timeline cells.
//!
//! The pipeline mirrors remend 1.3.1's default handlers. Raw Markdown remains
//! persisted separately by the timeline reducer, while this function prepares
//! only the additive rendered snapshot used by Flutter.

use regex::Regex;

mod codex_markdown_emphasis;
mod codex_markdown_links;
mod codex_markdown_math;
mod codex_markdown_scanner;

use codex_markdown_emphasis::{
    complete_bold, complete_bold_italic, complete_double_underscore, complete_single_asterisk,
    complete_single_underscore, complete_strikethrough,
};
use codex_markdown_links::complete_links_and_images;
use codex_markdown_math::complete_block_katex;
use codex_markdown_scanner::{is_escaped, is_in_code, is_word_char};

pub(super) fn normalize_markdown_newlines(text: &str) -> String {
    let normalized = text.replace("\r\n", "\n").replace('\r', "\n");
    let mut placeholders = Vec::new();
    let fence_pattern = Regex::new(r"```[\s\S]*?(?:```|$)").unwrap();
    let mut protected = fence_pattern
        .replace_all(&normalized, |captures: &regex::Captures<'_>| {
            placeholders.push(captures[0].to_string());
            format!("\0CB{}\0", placeholders.len() - 1)
        })
        .into_owned();
    if let Some(start) = protected.find("```") {
        placeholders.push(protected[start..].to_string());
        protected = format!("{}\0CB{}\0", &protected[..start], placeholders.len() - 1);
    }

    let block_line = |line: &str| {
        let line = line.trim_start();
        line.starts_with(['-', '*', '+', '>', '#', '|'])
            || line.starts_with("```")
            || line.starts_with("---")
            || line.starts_with("***")
            || line.starts_with("___")
            || line.starts_with("[ ] ")
            || line.starts_with("[x] ")
            || line.split_once('.').is_some_and(|(prefix, rest)| {
                !prefix.is_empty()
                    && prefix.chars().all(|character| character.is_ascii_digit())
                    && rest.starts_with(' ')
            })
    };
    let list_line = |line: &str| {
        let line = line.trim_start();
        line.starts_with("- ")
            || line.starts_with("* ")
            || line.starts_with("+ ")
            || line.starts_with("[ ] ")
            || line.starts_with("[x] ")
            || line.split_once('.').is_some_and(|(prefix, rest)| {
                !prefix.is_empty()
                    && prefix.chars().all(|character| character.is_ascii_digit())
                    && rest.starts_with(' ')
            })
    };
    let table_line = |line: &str| line.trim_start().starts_with('|');
    let paragraphs = protected.split("\n\n").filter(|part| !part.is_empty());
    let mut processed = Vec::new();
    for paragraph in paragraphs {
        let lines: Vec<&str> = paragraph.split('\n').collect();
        if lines.len() == 1 {
            processed.push(paragraph.to_string());
            continue;
        }
        let mut output = lines[0].to_string();
        for index in 1..lines.len() {
            let current = lines[index].trim_start();
            let previous = lines[index - 1].trim_start();
            if table_line(current)
                && table_line(previous)
                && !lines[index - 1].trim_end().ends_with('|')
            {
                output.push(' ');
            } else if block_line(current) || (block_line(previous) && !list_line(previous)) {
                output.push('\n');
            } else if !lines[index - 1].ends_with(' ') {
                output.push(' ');
            }
            output.push_str(lines[index]);
        }
        processed.push(output);
    }
    let mut rendered = String::new();
    for (index, paragraph) in processed.iter().enumerate() {
        if index > 0 {
            let previous = processed[index - 1]
                .rsplit('\n')
                .next()
                .unwrap_or_default()
                .trim_start();
            let current = paragraph.lines().next().unwrap_or_default().trim_start();
            let adjacent_list = list_line(previous) && list_line(current);
            let adjacent_table = table_line(previous) && table_line(current);
            rendered.push_str(if adjacent_list || adjacent_table {
                "\n"
            } else {
                "\n\n"
            });
        }
        rendered.push_str(paragraph);
    }
    for (index, block) in placeholders.iter().enumerate() {
        rendered = rendered.replace(&format!("\0CB{}\0", index), block);
    }
    Regex::new(r"\n{3,}")
        .unwrap()
        .replace_all(&rendered, "\n\n")
        .into_owned()
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
    result = complete_links_and_images(&result);
    if result.ends_with("](streamdown:incomplete-link)") {
        return result;
    }
    result = complete_bold_italic(&result);
    result = complete_bold(&result);
    result = complete_double_underscore(&result);
    result = complete_single_asterisk(&result);
    result = complete_single_underscore(&result);
    result = incomplete_inline_code(&result);
    result = complete_strikethrough(&result);
    complete_block_katex(&result)
}

fn single_tilde(text: &str) -> String {
    let mut result = String::with_capacity(text.len());
    for (index, character) in text.char_indices() {
        if character == '~'
            && !is_escaped(text, index)
            && !is_in_code(text, index)
            && index > 0
            && index + 1 < text.len()
            && text[..index].chars().next_back().is_some_and(is_word_char)
            && text[index + 1..].chars().next().is_some_and(is_word_char)
            && !text[..index].ends_with('~')
            && !text[index + 1..].starts_with('~')
        {
            result.push('\\');
        }
        result.push(character);
    }
    result
}

fn comparison_operators(text: &str) -> String {
    let pattern = Regex::new(r"(?m)^(\s*(?:[-*+]|\d+[.)]) +)>(=?\s*[$]?\d)").unwrap();
    pattern
        .replace_all(text, |captures: &regex::Captures<'_>| {
            let start = captures.get(0).map_or(0, |value| value.start());
            if is_in_code(text, start) {
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
        text.to_string()
    } else {
        text[..matched.start()].trim_end().to_string()
    }
}

fn incomplete_setext_heading(text: &str) -> String {
    let Some((previous, last)) = text.rsplit_once('\n') else {
        return text.to_string();
    };
    let trimmed = last.trim();
    let previous_has_content = previous
        .rsplit('\n')
        .next()
        .is_some_and(|line| !line.trim().is_empty());
    if previous_has_content
        && matches!(trimmed, "-" | "--" | "=" | "==")
        && !last.ends_with(char::is_whitespace)
    {
        format!("{text}\u{200b}")
    } else {
        text.to_string()
    }
}

fn incomplete_inline_code(text: &str) -> String {
    if !text.contains('\n')
        && text.starts_with("```")
        && text.ends_with("``")
        && !text.ends_with("```")
    {
        return format!("{text}`");
    }
    if codex_markdown_scanner::has_unclosed_fence(text) {
        return text.to_string();
    }
    let count = codex_markdown_scanner::count_single_backticks(text);
    if count == 0 || count.is_multiple_of(2) {
        return text.to_string();
    }
    let Some(opening) = text.char_indices().rev().find_map(|(index, character)| {
        (character == '`'
            && !is_escaped(text, index)
            && !codex_markdown_scanner::is_triple_backtick(text, index))
        .then_some(index)
    }) else {
        return text.to_string();
    };
    let content = &text[opening + 1..];
    if content.contains('`') || content.is_empty() || content.chars().all(char::is_whitespace) {
        text.to_string()
    } else {
        format!("{text}`")
    }
}

#[cfg(test)]
#[path = "codex_markdown_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "codex_markdown_fixture_tests.rs"]
mod fixture_tests;
