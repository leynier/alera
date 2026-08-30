use std::ops::Range;

use gpui::HighlightStyle;

#[derive(Clone, Debug)]
pub struct TerminalSearchQuery {
    needle: String,
    case_sensitive: bool,
}

impl TerminalSearchQuery {
    pub fn new(query: &str, case_sensitive: bool) -> Self {
        let query = query.trim();
        Self {
            needle: if case_sensitive {
                query.to_owned()
            } else {
                query.to_lowercase()
            },
            case_sensitive,
        }
    }

    pub fn is_empty(&self) -> bool {
        self.needle.is_empty()
    }

    pub fn ranges(&self, text: &str) -> Vec<Range<usize>> {
        if self.is_empty() {
            return Vec::new();
        }
        if self.case_sensitive {
            return text
                .match_indices(&self.needle)
                .map(|(start, value)| start..start + value.len())
                .collect();
        }
        let folded = text.to_lowercase();
        let mut source = Vec::new();
        let mut folded_offset = 0;
        for (offset, character) in text.char_indices() {
            for lower in character.to_lowercase() {
                source.push((folded_offset, offset..offset + character.len_utf8()));
                folded_offset += lower.len_utf8();
            }
        }
        let mut ranges: Vec<Range<usize>> = Vec::new();
        for (start, value) in folded.match_indices(&self.needle) {
            // Case conversion may expand a character (İ -> i + combining dot).
            let first = source.partition_point(|(offset, _)| *offset <= start) - 1;
            let last = source.partition_point(|(offset, _)| *offset < start + value.len()) - 1;
            let range = source[first].1.start..source[last].1.end;
            if ranges
                .last()
                .is_none_or(|previous| previous.end <= range.start)
            {
                ranges.push(range);
            }
        }
        ranges
    }
}

pub fn search_highlights(
    text: &str,
    base: Vec<(Range<usize>, HighlightStyle)>,
    query: &TerminalSearchQuery,
    background: gpui::Hsla,
) -> Vec<(Range<usize>, HighlightStyle)> {
    let matches = query.ranges(text);
    if matches.is_empty() {
        return base;
    }
    // Split existing ANSI runs so search overrides only the background, with
    // deterministic precedence and no overlapping runs passed to StyledText.
    let mut result = Vec::new();
    let mut match_index = 0;
    for (range, style) in base {
        if range.is_empty()
            || !text.is_char_boundary(range.start)
            || !text.is_char_boundary(range.end)
        {
            continue;
        }
        let mut start = range.start;
        while start < range.end {
            while matches.get(match_index).is_some_and(|hit| hit.end <= start) {
                match_index += 1;
            }
            let hit = matches.get(match_index).filter(|hit| hit.start < range.end);
            let (end, matched) = match hit {
                Some(hit) if hit.start <= start => (range.end.min(hit.end), true),
                Some(hit) => (hit.start, false),
                None => (range.end, false),
            };
            let mut segment_style = style;
            if matched {
                segment_style.background_color = Some(background);
            }
            result.push((start..end, segment_style));
            start = end;
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn folded_ranges_preserve_original_unicode_boundaries() {
        for (text, query, expected) in [
            ("İstanbul", "i", vec![0..2]),
            ("Kx KX", "kx", vec![0..4, 5..7]),
            ("Áé ÁÉ", "áé", vec![0..4, 5..9]),
            ("界e\u{301}界", "e\u{301}", vec![3..6]),
            ("iİi", "i", vec![0..1, 1..3, 3..4]),
            ("ΟΣ", "ος", vec![0..4]),
        ] {
            let ranges = TerminalSearchQuery::new(query, false).ranges(text);
            assert_eq!(ranges, expected, "{text}");
            for range in ranges {
                assert!(text.get(range).is_some());
            }
        }
        assert!(TerminalSearchQuery::new("", false).ranges("abc").is_empty());
        assert_eq!(
            TerminalSearchQuery::new("[x]", true).ranges("[X] [x]"),
            vec![4..7]
        );
    }

    #[test]
    fn search_runs_preserve_ansi_styles_and_cover_each_byte_once() {
        let text = "İ red red";
        let foreground = gpui::rgb(0xff0000).into();
        let old_background = gpui::rgb(0x0000ff).into();
        let background = gpui::rgb(0xffcc00).into();
        let style = HighlightStyle {
            color: Some(foreground),
            background_color: Some(old_background),
            font_weight: Some(gpui::FontWeight::BOLD),
            ..Default::default()
        };
        for query in ["i", "red", "not found"] {
            let query = TerminalSearchQuery::new(query, false);
            let expected = query.ranges(text);
            let runs = search_highlights(text, vec![(0..text.len(), style)], &query, background);
            let mut end = 0;
            for (range, actual) in &runs {
                assert_eq!(range.start, end);
                assert!(text.get(range.clone()).is_some());
                assert_eq!(actual.color, Some(foreground));
                assert_eq!(actual.font_weight, style.font_weight);
                let selected = expected
                    .iter()
                    .any(|hit| hit.start <= range.start && hit.end >= range.end);
                assert_eq!(
                    actual.background_color,
                    Some(if selected { background } else { old_background })
                );
                end = range.end;
            }
            assert_eq!(end, text.len());
            let _ = gpui::StyledText::new(text).with_highlights(runs);
        }
    }

    #[test]
    fn matches_can_cross_multiple_ansi_runs() {
        let query = TerminalSearchQuery::new("abc", false);
        let runs = search_highlights(
            "xabcx",
            vec![
                (0..2, HighlightStyle::default()),
                (2..5, HighlightStyle::default()),
            ],
            &query,
            gpui::rgb(0xffff00).into(),
        );
        assert_eq!(
            runs.iter()
                .map(|(range, _)| range.clone())
                .collect::<Vec<_>>(),
            vec![0..1, 1..2, 2..4, 4..5]
        );
    }
}
