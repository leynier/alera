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
        let mut balances = delimiter_balances(&body);
        let mut continued = import_continues(&body, balances);
        let mut candidates = vec![index];
        let mut cursor = index + 1;
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
            candidates.push(cursor);
            let delta = delimiter_balances(&next_body);
            for position in 0..balances.len() {
                balances[position] += delta[position];
            }
            continued = import_continues(&next_body, balances);
            cursor += 1;
        }
        if !continued {
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
    allows_import_keyword && trimmed.starts_with("import ")
        || allows_js_reexports && starts_reexport(trimmed)
        || allows_python_from_imports
            && trimmed.starts_with("from ")
            && trimmed.contains(" import ")
        || allows_rust_imports && (trimmed.starts_with("use ") || trimmed.starts_with("pub use "))
        || allows_c_includes
            && (trimmed.starts_with("#include ") || trimmed.starts_with("#include<"))
        || allows_common_js_imports
            && (trimmed.starts_with("require(")
                || trimmed.starts_with("const ") && trimmed.contains("require("))
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

fn delimiter_balances(value: &str) -> [i32; 3] {
    [
        count_byte(value.as_bytes(), b'(') - count_byte(value.as_bytes(), b')'),
        count_byte(value.as_bytes(), b'[') - count_byte(value.as_bytes(), b']'),
        count_byte(value.as_bytes(), b'{') - count_byte(value.as_bytes(), b'}'),
    ]
}

fn import_continues(value: &str, balances: [i32; 3]) -> bool {
    balances.iter().any(|balance| *balance != 0) || value.trim_end().ends_with('\\')
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

fn count_byte(value: &[u8], needle: u8) -> i32 {
    value.iter().filter(|byte| **byte == needle).count() as i32
}
