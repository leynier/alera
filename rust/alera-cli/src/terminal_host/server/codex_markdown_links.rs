use super::codex_markdown_scanner::{is_in_code, matching_close_bracket, matching_open_bracket};

const INCOMPLETE_LINK: &str = "streamdown:incomplete-link";

pub(super) fn complete_links_and_images(text: &str) -> String {
    if let Some(paren) = text.rfind("](") {
        if !is_in_code(text, paren) && !text[paren + 2..].contains(')') {
            if let Some(open) = matching_open_bracket(text, paren) {
                if !is_in_code(text, open) {
                    let image = open > 0 && text[..open].ends_with('!');
                    let start = if image { open - 1 } else { open };
                    if image {
                        return text[..start].to_string();
                    }
                    return format!(
                        "{}[{}]({INCOMPLETE_LINK})",
                        &text[..start],
                        &text[open + 1..paren]
                    );
                }
            }
        }
    }

    let mut open = text.len();
    while let Some(index) = previous_char_index(text, open) {
        open = index;
        if text[index..].starts_with('[') && !is_in_code(text, index) {
            if let Some(close) = matching_close_bracket(text, index) {
                if close + 1 < text.len() && text[close + 1..].starts_with('(') {
                    let url_start = close + 2;
                    if text[url_start..].contains(')') {
                        continue;
                    }
                }
                continue;
            }
            let image = index > 0 && text[..index].ends_with('!');
            if image {
                return text[..index - 1].to_string();
            }
            return format!("{text}]({INCOMPLETE_LINK})");
        }
    }
    text.to_string()
}

fn previous_char_index(text: &str, end: usize) -> Option<usize> {
    if end == 0 {
        return None;
    }
    let mut index = end.min(text.len());
    index -= text[..index].chars().next_back()?.len_utf8();
    Some(index)
}
