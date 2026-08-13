// SPDX-License-Identifier: Apache-2.0
// Ported and modified from Meat revision f39f41dfe7b5b37a12b35fdfbaecc7e779855bd3.

use super::ReadingDiffError;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum LineKind {
    Structural,
    HunkSource,
    NoNewline,
}

#[derive(Clone, Debug)]
pub(crate) struct SourceLine {
    pub text: Vec<u8>,
    pub eol: Vec<u8>,
    pub kind: LineKind,
    pub marker: Option<u8>,
    pub file_id: Option<usize>,
    pub hunk_id: Option<usize>,
    pub allows_common_js_imports: bool,
}

pub(crate) fn parse(raw: &[u8]) -> Result<Vec<SourceLine>, ReadingDiffError> {
    let mut lines = split_lines(raw);
    let mut file_id = None;
    let mut hunk_id = None;
    let mut next_file = 0usize;
    let mut next_hunk = 0usize;
    let mut remaining: Option<(usize, usize)> = None;
    let mut old_allows_common_js_imports = false;
    let mut new_allows_common_js_imports = false;

    for (index, line) in lines.iter_mut().enumerate() {
        let text = line.text.clone();
        if text.starts_with(b"diff --cc ") || text.starts_with(b"diff --combined ") {
            return Err(ReadingDiffError::new(format!(
                "Combined diff on line {} is unsupported; use a normal two-tree diff.",
                index + 1
            )));
        }
        if text.starts_with(b"diff --git ") {
            file_id = Some(next_file);
            next_file += 1;
            hunk_id = None;
            remaining = None;
            old_allows_common_js_imports = false;
            new_allows_common_js_imports = false;
        }
        if let Some(path) = text.strip_prefix(b"--- ") {
            old_allows_common_js_imports = is_common_js_path(path);
        }
        if let Some(path) = text.strip_prefix(b"+++ ") {
            new_allows_common_js_imports = is_common_js_path(path);
        }
        if text.starts_with(b"@@@") {
            return Err(ReadingDiffError::new(format!(
                "Combined diff hunk on line {} is unsupported; use a normal two-tree diff.",
                index + 1
            )));
        }
        if text.starts_with(b"@@ ") {
            let counts = parse_hunk_counts(&text).ok_or_else(|| {
                ReadingDiffError::new(format!("Malformed hunk header on line {}.", index + 1))
            })?;
            hunk_id = Some(next_hunk);
            next_hunk += 1;
            remaining = Some(counts);
            line.file_id = file_id;
            line.hunk_id = hunk_id;
            continue;
        }
        line.file_id = file_id;
        line.hunk_id = hunk_id;
        if text == b"\\ No newline at end of file" {
            line.kind = LineKind::NoNewline;
            continue;
        }
        let Some((old_remaining, new_remaining)) = remaining.as_mut() else {
            continue;
        };
        if *old_remaining == 0 && *new_remaining == 0 {
            remaining = None;
            hunk_id = None;
            line.hunk_id = None;
            continue;
        }
        let Some(marker) = text.first().copied() else {
            return Err(ReadingDiffError::new(format!(
                "Empty source row in hunk on line {}.",
                index + 1
            )));
        };
        match marker {
            b' ' => {
                *old_remaining = old_remaining.saturating_sub(1);
                *new_remaining = new_remaining.saturating_sub(1);
            }
            b'-' => *old_remaining = old_remaining.saturating_sub(1),
            b'+' => *new_remaining = new_remaining.saturating_sub(1),
            _ => {
                return Err(ReadingDiffError::new(format!(
                    "Unexpected hunk row on line {}.",
                    index + 1
                )))
            }
        }
        line.kind = LineKind::HunkSource;
        line.marker = Some(marker);
        line.allows_common_js_imports = match marker {
            b'-' => old_allows_common_js_imports,
            b'+' => new_allows_common_js_imports,
            _ => old_allows_common_js_imports && new_allows_common_js_imports,
        };
    }
    if remaining.is_some_and(|(old, new)| old != 0 || new != 0) {
        return Err(ReadingDiffError::new(
            "The final hunk counts are inconsistent with its source rows.",
        ));
    }
    Ok(lines)
}

fn split_lines(raw: &[u8]) -> Vec<SourceLine> {
    if raw.is_empty() {
        return Vec::new();
    }
    let mut result = Vec::new();
    let mut start = 0usize;
    for (index, byte) in raw.iter().enumerate() {
        if *byte != b'\n' {
            continue;
        }
        let content_end = if index > start && raw[index - 1] == b'\r' {
            index - 1
        } else {
            index
        };
        result.push(SourceLine {
            text: raw[start..content_end].to_vec(),
            eol: raw[content_end..=index].to_vec(),
            kind: LineKind::Structural,
            marker: None,
            file_id: None,
            hunk_id: None,
            allows_common_js_imports: false,
        });
        start = index + 1;
    }
    if start < raw.len() {
        result.push(SourceLine {
            text: raw[start..].to_vec(),
            eol: Vec::new(),
            kind: LineKind::Structural,
            marker: None,
            file_id: None,
            hunk_id: None,
            allows_common_js_imports: false,
        });
    }
    result
}

fn is_common_js_path(path: &[u8]) -> bool {
    let path = path.split(|byte| *byte == b'\t').next().unwrap_or(path);
    if path == b"/dev/null" {
        return false;
    }
    let path = path.strip_suffix(b"\"").unwrap_or(path);
    let extension = path.rsplit(|byte| *byte == b'.').next().unwrap_or_default();
    [
        b"js".as_slice(),
        b"cjs",
        b"mjs",
        b"jsx",
        b"ts",
        b"cts",
        b"mts",
        b"tsx",
    ]
    .iter()
    .any(|candidate| extension.eq_ignore_ascii_case(candidate))
}

fn parse_hunk_counts(line: &[u8]) -> Option<(usize, usize)> {
    let text = std::str::from_utf8(line).ok()?;
    let body = text.strip_prefix("@@ ")?;
    let closing = body.find(" @@")?;
    let mut parts = body[..closing].split_whitespace();
    let old = parse_range_count(parts.next()?, '-')?;
    let new = parse_range_count(parts.next()?, '+')?;
    Some((old, new))
}

fn parse_range_count(value: &str, marker: char) -> Option<usize> {
    let value = value.strip_prefix(marker)?;
    let count = value.split_once(',').map_or("1", |(_, count)| count);
    count.parse().ok()
}

pub(crate) fn numbered(raw: &[u8]) -> Result<String, ReadingDiffError> {
    let lines = parse(raw)?;
    let width = lines.len().max(1).to_string().len();
    let mut output = String::new();
    for (index, line) in lines.iter().enumerate() {
        let text = String::from_utf8_lossy(&line.text);
        output.push_str(&format!("{:>width$}|{text}\n", index + 1));
    }
    Ok(output)
}

pub(crate) fn source_body(line: &SourceLine) -> &[u8] {
    line.text.get(1..).unwrap_or_default()
}
