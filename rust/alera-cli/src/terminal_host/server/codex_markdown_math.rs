use super::codex_markdown_scanner::{is_directly_escaped, is_in_code};

pub(super) fn complete_block_katex(text: &str) -> String {
    let mut pairs = 0;
    let mut index = 0;
    while index < text.len() {
        if text[index..].starts_with("```") && !is_directly_escaped(text, index) {
            index += 3;
            while index < text.len()
                && (!text[index..].starts_with("```") || is_directly_escaped(text, index))
            {
                index += text[index..]
                    .chars()
                    .next()
                    .map(char::len_utf8)
                    .unwrap_or(1);
            }
            index = (index + 3).min(text.len());
            continue;
        }
        if text[index..].starts_with("$$")
            && !is_directly_escaped(text, index)
            && !is_in_code(text, index)
        {
            pairs += 1;
            index += 2;
            continue;
        }
        index += text[index..]
            .chars()
            .next()
            .map(char::len_utf8)
            .unwrap_or(1);
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
