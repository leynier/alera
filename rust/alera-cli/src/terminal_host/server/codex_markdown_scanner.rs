pub(super) fn is_escaped(text: &str, byte_index: usize) -> bool {
    let bytes = text.as_bytes();
    let mut index = byte_index.min(bytes.len());
    let mut slashes = 0;
    while index > 0 && bytes[index - 1] == b'\\' {
        slashes += 1;
        index -= 1;
    }
    slashes % 2 == 1
}

pub(super) fn is_directly_escaped(text: &str, byte_index: usize) -> bool {
    byte_index > 0 && text.as_bytes().get(byte_index - 1) == Some(&b'\\')
}

pub(super) fn is_triple_backtick(text: &str, index: usize) -> bool {
    let bytes = text.as_bytes();
    (index >= 2 && bytes[index - 2..=index] == *b"```")
        || (index > 0 && index + 1 < bytes.len() && bytes[index - 1..=index + 1] == *b"```")
        || bytes
            .get(index..)
            .is_some_and(|tail| tail.starts_with(b"```"))
}

pub(super) fn has_unclosed_fence(text: &str) -> bool {
    let mut count = 0;
    let mut index = 0;
    while let Some(offset) = text[index..].find("```") {
        let byte_index = index + offset;
        if !is_directly_escaped(text, byte_index) {
            count += 1;
        }
        index = byte_index + 3;
        if index >= text.len() {
            break;
        }
    }
    count % 2 == 1
}

pub(super) fn is_in_code(text: &str, byte_index: usize) -> bool {
    let mut fenced = false;
    let mut inline = false;
    let mut index = 0;
    while index < byte_index && index < text.len() {
        if text[index..].starts_with("```") && !is_directly_escaped(text, index) {
            fenced = !fenced;
            index += 3;
            continue;
        }
        if !fenced && text[index..].starts_with('`') && !is_directly_escaped(text, index) {
            inline = !inline;
        }
        index += text[index..]
            .chars()
            .next()
            .map(char::len_utf8)
            .unwrap_or(1);
    }
    fenced || inline
}

pub(super) fn is_word_char(character: char) -> bool {
    character == '_' || character.is_alphanumeric()
}

pub(super) fn meaningful(content: &str) -> bool {
    content
        .chars()
        .any(|character| !character.is_whitespace() && !"_*~`".contains(character))
}

pub(super) fn only_markers_or_whitespace(content: &str) -> bool {
    content
        .chars()
        .all(|character| character.is_whitespace() || "_*~`".contains(character))
}

pub(super) fn is_horizontal_rule(text: &str, marker_index: usize, marker: char) -> bool {
    let line_start = text[..marker_index]
        .rfind('\n')
        .map_or(0, |index| index + 1);
    let line_end = text[marker_index..]
        .find('\n')
        .map_or(text.len(), |index| marker_index + index);
    let line = &text[line_start..line_end];
    let mut markers = 0;
    for character in line.chars() {
        if character == marker {
            markers += 1;
        } else if !character.is_whitespace() {
            return false;
        }
    }
    markers >= 3
}

pub(super) fn matching_open_bracket(text: &str, close: usize) -> Option<usize> {
    let mut depth = 1;
    let mut index = close;
    while index > 0 {
        index -= text[..index]
            .chars()
            .next_back()
            .map(char::len_utf8)
            .unwrap_or(1);
        match text[index..].chars().next()? {
            ']' => depth += 1,
            '[' => {
                depth -= 1;
                if depth == 0 {
                    return Some(index);
                }
            }
            _ => {}
        }
    }
    None
}

pub(super) fn matching_close_bracket(text: &str, open: usize) -> Option<usize> {
    let mut depth = 1;
    let mut index = open + 1;
    while index < text.len() {
        let character = text[index..].chars().next()?;
        match character {
            '[' => depth += 1,
            ']' => {
                depth -= 1;
                if depth == 0 {
                    return Some(index);
                }
            }
            _ => {}
        }
        index += character.len_utf8();
    }
    None
}

pub(super) fn is_within_math(text: &str, position: usize) -> bool {
    let mut inline = false;
    let mut block = false;
    let mut index = 0;
    while index < position && index < text.len() {
        if text[index..].starts_with('\\') {
            index += text[index..]
                .chars()
                .nth(1)
                .map(char::len_utf8)
                .map(|width| width + 1)
                .unwrap_or(1);
            continue;
        }
        if text[index..].starts_with("$$") {
            block = !block;
            inline = false;
            index += 2;
        } else if text[index..].starts_with('$') && !block {
            inline = !inline;
            index += 1;
        } else {
            index += text[index..]
                .chars()
                .next()
                .map(char::len_utf8)
                .unwrap_or(1);
        }
    }
    inline || block
}

pub(super) fn is_within_link_url(text: &str, position: usize) -> bool {
    let mut index = position;
    while index > 0 {
        index -= text[..index]
            .chars()
            .next_back()
            .map(char::len_utf8)
            .unwrap_or(1);
        match text[index..].chars().next() {
            Some(')') => return false,
            Some('(') if index > 0 && text[..index].ends_with(']') => {
                return text[index + 1..position].find('\n').is_none();
            }
            Some('\n') => return false,
            _ => {}
        }
    }
    false
}

pub(super) fn is_within_html_tag(text: &str, position: usize) -> bool {
    let mut index = position;
    while index > 0 {
        index -= text[..index]
            .chars()
            .next_back()
            .map(char::len_utf8)
            .unwrap_or(1);
        match text[index..].chars().next() {
            Some('>') => return false,
            Some('<') => {
                return text[index + 1..]
                    .chars()
                    .next()
                    .is_some_and(|character| character.is_ascii_alphabetic() || character == '/');
            }
            Some('\n') => return false,
            _ => {}
        }
    }
    false
}

pub(super) fn count_unescaped_outside_code(text: &str, marker: &str) -> usize {
    let mut count = 0;
    let mut index = 0;
    while let Some(offset) = text[index..].find(marker) {
        let byte_index = index + offset;
        if !is_in_code(text, byte_index) {
            count += 1;
        }
        index = byte_index + marker.len();
        if index >= text.len() {
            break;
        }
    }
    count
}

pub(super) fn count_single_backticks(text: &str) -> usize {
    text.char_indices()
        .filter(|(index, character)| {
            *character == '`'
                && !is_triple_backtick(text, *index)
                && !is_directly_escaped(text, *index)
        })
        .count()
}
