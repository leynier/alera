pub(super) struct LineRanges {
    ranges: Vec<LineRange>,
}

impl LineRanges {
    pub(super) fn new(content: &str) -> Self {
        let mut ranges = Vec::new();
        let mut start = 0;
        for line in content.split_inclusive('\n') {
            let mut end = start + line.len();
            if line.ends_with('\n') {
                end -= 1;
            }
            if end > start && content.as_bytes()[end - 1] == b'\r' {
                end -= 1;
            }
            ranges.push(LineRange { start, end });
            start += line.len();
        }
        Self { ranges }
    }

    pub(super) fn locate_match_range(
        &self,
        content: &str,
        line_number: u32,
        column: u32,
        match_length: u32,
    ) -> Option<(usize, usize)> {
        let line = self.ranges.get(line_number.checked_sub(1)? as usize)?;
        let clean_line = &content[line.start..line.end];
        let start_col = column.saturating_sub(1) as usize;
        let start_byte = byte_offset_for_char(clean_line, start_col);
        let end_byte = byte_offset_for_char(clean_line, start_col + match_length as usize);
        Some((line.start + start_byte, line.start + end_byte))
    }

    pub(super) fn match_slice<'a>(
        &self,
        content: &'a str,
        line_number: u32,
        column: u32,
        match_length: u32,
    ) -> Option<&'a str> {
        let (start, end) = self.locate_match_range(content, line_number, column, match_length)?;
        content.get(start..end)
    }
}

struct LineRange {
    start: usize,
    end: usize,
}

fn byte_offset_for_char(text: &str, char_offset: usize) -> usize {
    text.char_indices()
        .nth(char_offset)
        .map(|(byte, _)| byte)
        .unwrap_or(text.len())
}
