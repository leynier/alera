use super::{WorkspaceEditorTextFile, WorkspaceTextFile};

pub(super) fn editor_text_file_from_raw(
    file: WorkspaceTextFile,
    tab_size: i32,
) -> WorkspaceEditorTextFile {
    let display_content = expand_workspace_editor_tabs(&file.content, tab_size);
    WorkspaceEditorTextFile {
        raw_content: file.content,
        display_content,
        content_token: file.content_token,
        modified_millis: file.modified_millis,
        size: file.size,
    }
}

pub(super) fn encode_workspace_editor_text_for_save(
    current_display_content: &str,
    original_raw_content: Option<&str>,
    original_display_content: Option<&str>,
) -> String {
    let (Some(original_raw_content), Some(original_display_content)) =
        (original_raw_content, original_display_content)
    else {
        return current_display_content.to_string();
    };
    if current_display_content == original_display_content {
        return original_raw_content.to_string();
    }

    let original_raw_segments = split_line_segments(original_raw_content);
    let original_display_segments = split_line_segments(original_display_content);
    let current_segments = split_line_segments(current_display_content);
    if original_raw_segments.len() != original_display_segments.len() {
        return current_display_content.to_string();
    }

    let mut prefix = 0usize;
    while prefix < original_display_segments.len()
        && prefix < current_segments.len()
        && original_display_segments[prefix] == current_segments[prefix]
    {
        prefix += 1;
    }

    let mut suffix = 0usize;
    while suffix < original_display_segments.len().saturating_sub(prefix)
        && suffix < current_segments.len().saturating_sub(prefix)
    {
        let original_index = original_display_segments.len() - suffix - 1;
        let current_index = current_segments.len() - suffix - 1;
        if original_display_segments[original_index] != current_segments[current_index] {
            break;
        }
        suffix += 1;
    }

    let mut encoded = String::with_capacity(current_display_content.len());
    let suffix_start = current_segments.len().saturating_sub(suffix);
    for (index, current_segment) in current_segments.iter().enumerate() {
        if index < prefix {
            encoded.push_str(original_raw_segments[index]);
        } else if index >= suffix_start {
            let original_index = original_raw_segments.len() - (current_segments.len() - index);
            encoded.push_str(original_raw_segments[original_index]);
        } else {
            encoded.push_str(current_segment);
        }
    }
    encoded
}

fn expand_workspace_editor_tabs(text: &str, tab_size: i32) -> String {
    let effective_tab_size = normalize_workspace_editor_tab_size(tab_size);
    let mut expanded = String::with_capacity(text.len());
    let mut column = 0usize;
    for character in text.chars() {
        if character == '\t' {
            let spaces = effective_tab_size - (column % effective_tab_size);
            expanded.extend(std::iter::repeat_n(' ', spaces));
            column += spaces;
        } else {
            expanded.push(character);
            if character == '\n' || character == '\r' {
                column = 0;
            } else {
                column += 1;
            }
        }
    }
    expanded
}

fn normalize_workspace_editor_tab_size(tab_size: i32) -> usize {
    tab_size.clamp(1, 8) as usize
}

fn split_line_segments(text: &str) -> Vec<&str> {
    let mut segments = Vec::new();
    let mut start = 0usize;
    let bytes = text.as_bytes();
    let mut index = 0usize;
    while index < bytes.len() {
        if bytes[index] == b'\r' {
            if index + 1 < bytes.len() && bytes[index + 1] == b'\n' {
                index += 1;
            }
            segments.push(&text[start..=index]);
            start = index + 1;
        } else if bytes[index] == b'\n' {
            segments.push(&text[start..=index]);
            start = index + 1;
        }
        index += 1;
    }
    if start < text.len() {
        segments.push(&text[start..]);
    }
    segments
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn expands_workspace_editor_tabs_to_columns() {
        assert_eq!(expand_workspace_editor_tabs("\talpha", 4), "    alpha");
        assert_eq!(expand_workspace_editor_tabs("a\tbeta", 4), "a   beta");
        assert_eq!(
            expand_workspace_editor_tabs("abcd\tbeta", 4),
            "abcd    beta"
        );
        assert_eq!(expand_workspace_editor_tabs("a\r\n\tb", 2), "a\r\n  b");
        assert_eq!(expand_workspace_editor_tabs("\tx", 0), " x");
        assert_eq!(expand_workspace_editor_tabs("\tx", 99), "        x");
    }

    #[test]
    fn encodes_workspace_editor_text_without_touching_unchanged_raw_tabs() {
        let raw = "\talpha\n\tbeta\n";
        let display = expand_workspace_editor_tabs(raw, 4);

        assert_eq!(
            encode_workspace_editor_text_for_save(&display, Some(raw), Some(&display)),
            raw
        );
    }

    #[test]
    fn encodes_workspace_editor_text_preserving_unchanged_edges() {
        let raw = "\talpha\n\tbeta\n\tgamma\n";
        let display = expand_workspace_editor_tabs(raw, 4);
        let edited = "    alpha\n    beta changed\n    gamma\n";

        assert_eq!(
            encode_workspace_editor_text_for_save(edited, Some(raw), Some(&display)),
            "\talpha\n    beta changed\n\tgamma\n"
        );
    }

    #[test]
    fn encodes_workspace_editor_text_falls_back_without_original_snapshots() {
        assert_eq!(
            encode_workspace_editor_text_for_save("    alpha\n", None, None),
            "    alpha\n"
        );
    }
}
