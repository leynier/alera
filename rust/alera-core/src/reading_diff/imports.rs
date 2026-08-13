// SPDX-License-Identifier: Apache-2.0
// Ported and modified from Meat revision f39f41dfe7b5b37a12b35fdfbaecc7e779855bd3.

use std::collections::HashSet;

use super::diff::{source_body, LineKind, SourceLine};

pub(crate) fn mandatory_import_mask(lines: &[SourceLine]) -> Vec<bool> {
    let mut hidden = vec![false; lines.len()];
    let mut index = 0usize;
    while index < lines.len() {
        let line = &lines[index];
        if line.kind != LineKind::HunkSource || !matches!(line.marker, Some(b'+' | b'-')) {
            index += 1;
            continue;
        }
        let body = String::from_utf8_lossy(source_body(line));
        if !starts_import(
            body.trim_start(),
            line.allows_import_keyword,
            line.allows_python_from_imports,
            line.allows_js_reexports,
            line.allows_c_includes,
            line.allows_common_js_imports,
            line.allows_rust_imports,
        ) {
            index += 1;
            continue;
        }
        let marker = line.marker;
        let mut scan = scan_import_syntax(&body, [0; 3], line.allows_python_from_imports);
        if !scan.reliable || scan.has_trailing_statement {
            index += 1;
            continue;
        }
        let mut continued = scan.continues();
        let mut candidates = vec![index];
        let mut cursor = index + 1;
        let mut import_only = true;
        while continued && cursor < lines.len() {
            let next = &lines[cursor];
            if next.kind != LineKind::HunkSource
                || next.file_id != line.file_id
                || next.hunk_id != line.hunk_id
            {
                break;
            }
            if next.marker != marker && next.marker != Some(b' ') {
                cursor += 1;
                continue;
            }
            let next_body = String::from_utf8_lossy(source_body(next));
            scan = scan_import_syntax(&next_body, scan.balances, line.allows_python_from_imports);
            if !scan.reliable || scan.has_trailing_statement {
                import_only = false;
                break;
            }
            candidates.push(cursor);
            continued = scan.continues();
            cursor += 1;
        }
        if import_only && !continued {
            for candidate in candidates {
                hidden[candidate] = true;
            }
        }
        index += 1;
    }
    hide_import_only_sections(lines, &mut hidden);
    hidden
}

fn starts_import(
    trimmed: &str,
    allows_import_keyword: bool,
    allows_python_from_imports: bool,
    allows_js_reexports: bool,
    allows_c_includes: bool,
    allows_common_js_imports: bool,
    allows_rust_imports: bool,
) -> bool {
    allows_import_keyword && starts_static_import(trimmed, allows_js_reexports)
        || allows_js_reexports && starts_reexport(trimmed)
        || allows_python_from_imports
            && trimmed.starts_with("from ")
            && trimmed.contains(" import ")
        || allows_rust_imports && (trimmed.starts_with("use ") || trimmed.starts_with("pub use "))
        || allows_c_includes
            && (trimmed.starts_with("#include ") || trimmed.starts_with("#include<"))
        || allows_common_js_imports && starts_common_js_import(trimmed)
}

fn starts_common_js_import(trimmed: &str) -> bool {
    if trimmed.starts_with("require(") {
        return true;
    }
    let Some(declaration) = trimmed.strip_prefix("const ") else {
        return false;
    };
    let Some(require_index) = declaration.find("require(") else {
        return false;
    };
    declaration[..require_index].trim_end().ends_with('=')
        && common_js_require_suffix_is_empty(&declaration[require_index..])
}

fn common_js_require_suffix_is_empty(require_call: &str) -> bool {
    let bytes = require_call.as_bytes();
    let mut index = "require(".len();
    let mut depth = 1usize;
    while index < bytes.len() {
        match bytes[index] {
            b'\'' | b'"' | b'`' => {
                let quote = bytes[index];
                index += 1;
                while index < bytes.len() {
                    match bytes[index] {
                        b'\\' => index = (index + 2).min(bytes.len()),
                        candidate if candidate == quote => {
                            index += 1;
                            break;
                        }
                        _ => index += 1,
                    }
                }
            }
            b'(' => {
                depth += 1;
                index += 1;
            }
            b')' => {
                depth -= 1;
                index += 1;
                if depth == 0 {
                    let suffix = require_call[index..].trim_start();
                    return suffix.is_empty() || suffix == ";" || suffix.starts_with("//");
                }
            }
            _ => index += 1,
        }
    }
    false
}

fn starts_static_import(trimmed: &str, javascript: bool) -> bool {
    let Some(rest) = trimmed.strip_prefix("import ") else {
        return false;
    };
    let rest = rest.trim_start();
    !rest.is_empty() && (!javascript || !rest.starts_with(['(', '/']))
}

fn starts_reexport(trimmed: &str) -> bool {
    let Some(rest) = trimmed.strip_prefix("export") else {
        return false;
    };
    let rest = rest.trim_start();
    if starts_brace_reexport(rest) || rest.starts_with("* from ") {
        return true;
    }
    let Some(rest) = rest.strip_prefix("type") else {
        return false;
    };
    let rest = rest.trim_start();
    starts_brace_reexport(rest) || rest.starts_with("* from ")
}

fn starts_brace_reexport(value: &str) -> bool {
    value.starts_with('{')
        && value
            .rfind('}')
            .is_some_and(|end| value[end + 1..].trim_start().starts_with("from "))
}

#[derive(Clone, Copy)]
struct ImportSyntaxScan {
    balances: [i32; 3],
    explicit_continuation: bool,
    has_trailing_statement: bool,
    reliable: bool,
}

impl ImportSyntaxScan {
    fn continues(self) -> bool {
        self.balances.iter().any(|balance| *balance != 0) || self.explicit_continuation
    }
}

fn scan_import_syntax(
    value: &str,
    mut balances: [i32; 3],
    hash_comments: bool,
) -> ImportSyntaxScan {
    let bytes = value.as_bytes();
    let mut index = 0usize;
    let mut after_terminator = false;
    let mut has_trailing_statement = false;
    let mut reliable = true;
    let mut last_syntax = None;
    while index < bytes.len() {
        let byte = bytes[index];
        if byte.is_ascii_whitespace() {
            index += 1;
            continue;
        }
        if hash_comments && byte == b'#' || byte == b'/' && bytes.get(index + 1) == Some(&b'/') {
            break;
        }
        if byte == b'/' && bytes.get(index + 1) == Some(&b'*') {
            let Some(relative_end) = bytes[index + 2..]
                .windows(2)
                .position(|window| window == b"*/")
            else {
                reliable = false;
                break;
            };
            index += relative_end + 4;
            continue;
        }
        if matches!(byte, b'\'' | b'"' | b'`') {
            if after_terminator {
                has_trailing_statement = true;
            }
            let quote = byte;
            index += 1;
            let mut closed = false;
            while index < bytes.len() {
                match bytes[index] {
                    b'\\' => index = (index + 2).min(bytes.len()),
                    candidate if candidate == quote => {
                        index += 1;
                        closed = true;
                        break;
                    }
                    _ => index += 1,
                }
            }
            if !closed {
                reliable = false;
                break;
            }
            last_syntax = Some(quote);
            continue;
        }
        match byte {
            b'(' => balances[0] += 1,
            b')' => balances[0] -= 1,
            b'[' => balances[1] += 1,
            b']' => balances[1] -= 1,
            b'{' => balances[2] += 1,
            b'}' => balances[2] -= 1,
            b';' if balances == [0, 0, 0] => after_terminator = true,
            _ if after_terminator => has_trailing_statement = true,
            _ => {}
        }
        last_syntax = Some(byte);
        index += 1;
    }
    ImportSyntaxScan {
        balances,
        explicit_continuation: last_syntax == Some(b'\\'),
        has_trailing_statement,
        reliable,
    }
}

pub(crate) fn hide_import_only_sections(lines: &[SourceLine], hidden: &mut [bool]) {
    let hunk_ids = lines
        .iter()
        .filter_map(|line| line.hunk_id)
        .collect::<HashSet<_>>();
    for hunk_id in hunk_ids {
        let changed = lines
            .iter()
            .enumerate()
            .filter(|(_, line)| {
                line.hunk_id == Some(hunk_id) && matches!(line.marker, Some(b'+' | b'-'))
            })
            .map(|(index, _)| index)
            .collect::<Vec<_>>();
        if !changed.is_empty() && changed.iter().all(|index| hidden[*index]) {
            for (index, line) in lines.iter().enumerate() {
                if line.hunk_id == Some(hunk_id) {
                    hidden[index] = true;
                }
            }
        }
    }
    let file_ids = lines
        .iter()
        .filter_map(|line| line.file_id)
        .collect::<HashSet<_>>();
    for file_id in file_ids {
        let hunks = lines
            .iter()
            .enumerate()
            .filter(|(_, line)| line.file_id == Some(file_id) && line.text.starts_with(b"@@ "))
            .map(|(index, _)| index)
            .collect::<Vec<_>>();
        if !hunks.is_empty() && hunks.iter().all(|index| hidden[*index]) {
            for (index, line) in lines.iter().enumerate() {
                if line.file_id == Some(file_id) {
                    hidden[index] = true;
                }
            }
        }
    }
}
