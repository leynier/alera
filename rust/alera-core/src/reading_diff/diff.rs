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
    pub allows_import_keyword: bool,
    pub allows_python_from_imports: bool,
    pub allows_js_reexports: bool,
    pub allows_c_includes: bool,
    pub allows_common_js_imports: bool,
    pub allows_rust_imports: bool,
}

pub(crate) fn parse(raw: &[u8]) -> Result<Vec<SourceLine>, ReadingDiffError> {
    let mut lines = split_lines(raw);
    let mut file_id = None;
    let mut hunk_id = None;
    let mut next_file = 0usize;
    let mut next_hunk = 0usize;
    let mut remaining: Option<(usize, usize)> = None;
    let mut old_import_syntax = ImportSyntax::default();
    let mut new_import_syntax = ImportSyntax::default();
    let mut old_allows_common_js_imports = false;
    let mut new_allows_common_js_imports = false;
    let mut old_allows_rust_imports = false;
    let mut new_allows_rust_imports = false;

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
            old_import_syntax = ImportSyntax::default();
            new_import_syntax = ImportSyntax::default();
            old_allows_common_js_imports = false;
            new_allows_common_js_imports = false;
            old_allows_rust_imports = false;
            new_allows_rust_imports = false;
        }
        if let Some(path) = text.strip_prefix(b"--- ") {
            old_import_syntax = import_syntax_for_path(path);
            old_allows_common_js_imports = is_common_js_path(path);
            old_allows_rust_imports = is_rust_path(path);
        }
        if let Some(path) = text.strip_prefix(b"+++ ") {
            new_import_syntax = import_syntax_for_path(path);
            new_allows_common_js_imports = is_common_js_path(path);
            new_allows_rust_imports = is_rust_path(path);
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
        let import_syntax = match marker {
            b'-' => old_import_syntax,
            b'+' => new_import_syntax,
            _ => old_import_syntax.intersection(new_import_syntax),
        };
        line.allows_import_keyword = import_syntax.import_keyword;
        line.allows_python_from_imports = import_syntax.python_from;
        line.allows_js_reexports = import_syntax.js_reexport;
        line.allows_c_includes = import_syntax.c_include;
        line.allows_common_js_imports = match marker {
            b'-' => old_allows_common_js_imports,
            b'+' => new_allows_common_js_imports,
            _ => old_allows_common_js_imports && new_allows_common_js_imports,
        };
        line.allows_rust_imports = match marker {
            b'-' => old_allows_rust_imports,
            b'+' => new_allows_rust_imports,
            _ => old_allows_rust_imports && new_allows_rust_imports,
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
            allows_import_keyword: false,
            allows_python_from_imports: false,
            allows_js_reexports: false,
            allows_c_includes: false,
            allows_common_js_imports: false,
            allows_rust_imports: false,
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
            allows_import_keyword: false,
            allows_python_from_imports: false,
            allows_js_reexports: false,
            allows_c_includes: false,
            allows_common_js_imports: false,
            allows_rust_imports: false,
        });
    }
    result
}

#[derive(Clone, Copy, Default)]
struct ImportSyntax {
    import_keyword: bool,
    python_from: bool,
    js_reexport: bool,
    c_include: bool,
}

impl ImportSyntax {
    fn intersection(self, other: Self) -> Self {
        Self {
            import_keyword: self.import_keyword && other.import_keyword,
            python_from: self.python_from && other.python_from,
            js_reexport: self.js_reexport && other.js_reexport,
            c_include: self.c_include && other.c_include,
        }
    }
}

fn import_syntax_for_path(path: &[u8]) -> ImportSyntax {
    let python = path_has_extension(path, &[b"py", b"pyi"]);
    let javascript = is_common_js_path(path);
    let import_keyword = python
        || javascript
        || path_has_extension(
            path,
            &[
                b"dart", b"java", b"kt", b"kts", b"go", b"swift", b"scala", b"groovy", b"cc",
                b"cpp", b"cxx", b"ixx", b"cppm",
            ],
        );
    let c_include = path_has_extension(
        path,
        &[
            b"c", b"h", b"cc", b"cpp", b"cxx", b"hh", b"hpp", b"hxx", b"m", b"mm",
        ],
    );
    ImportSyntax {
        import_keyword,
        python_from: python,
        js_reexport: javascript,
        c_include,
    }
}

fn is_common_js_path(path: &[u8]) -> bool {
    path_has_extension(
        path,
        &[b"js", b"cjs", b"mjs", b"jsx", b"ts", b"cts", b"mts", b"tsx"],
    )
}

fn is_rust_path(path: &[u8]) -> bool {
    path_has_extension(path, &[b"rs"])
}

fn path_has_extension(path: &[u8], extensions: &[&[u8]]) -> bool {
    let path = path.split(|byte| *byte == b'\t').next().unwrap_or(path);
    if path == b"/dev/null" {
        return false;
    }
    let path = path.strip_suffix(b"\"").unwrap_or(path);
    let extension = path.rsplit(|byte| *byte == b'.').next().unwrap_or_default();
    extensions
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
