// SPDX-License-Identifier: Apache-2.0
// Ported and modified from Meat revision f39f41dfe7b5b37a12b35fdfbaecc7e779855bd3.

use std::collections::{HashMap, HashSet};

use super::diff::{parse, source_body, LineKind, SourceLine};
use super::imports::mandatory_import_mask;
use super::plan::{LineRange, LineReplacement, Plan};
use super::ReadingDiffError;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CompileResult {
    pub reading_diff: Vec<u8>,
    pub summary: String,
    pub changed_lines: u32,
    pub retained_changed_lines: u32,
}

pub fn compile(raw: &[u8], plan_json: &str) -> Result<CompileResult, ReadingDiffError> {
    compile_with_source(raw, raw, plan_json)
}

pub fn compile_with_source(
    raw: &[u8],
    source_diff: &[u8],
    plan_json: &str,
) -> Result<CompileResult, ReadingDiffError> {
    let plan = Plan::parse(plan_json)?;
    let lines = parse(raw)?;
    if lines.is_empty() {
        return Err(ReadingDiffError::new("The diff is empty."));
    }

    let mut hidden = mandatory_import_mask(&lines);
    let mut folded_at = HashMap::<usize, Vec<u8>>::new();
    let mut ownership = vec![None::<&'static str>; lines.len()];
    for (index, is_hidden) in hidden.iter().copied().enumerate() {
        if is_hidden {
            ownership[index] = Some("automatic import elision");
        }
    }

    for (index, range) in plan.remove.iter().enumerate() {
        validate_range(&lines, *range, "remove", index)?;
        protect_python_structure(&lines, *range, "remove", index)?;
        claim_range(&mut hidden, &mut ownership, *range, "remove", index, true)?;
    }
    for (index, range) in plan.fold.iter().enumerate() {
        validate_range(&lines, *range, "fold", index)?;
        if range.start_line == range.end_line {
            return Err(ReadingDiffError::new(format!(
                "fold[{index}] must contain at least two source rows."
            )));
        }
        validate_fold(&lines, *range, index)?;
        protect_python_structure(&lines, *range, "fold", index)?;
        claim_range(&mut hidden, &mut ownership, *range, "fold", index, true)?;
        folded_at.insert(
            range.start_line - 1,
            fold_line(&lines[range.start_line - 1]),
        );
    }

    validate_move_symmetry(&lines, &hidden)?;
    validate_cross_chunk_move_retention(source_diff, &lines, &hidden)?;
    let replacements = validate_replacements(&lines, &hidden, &plan.replace)?;
    hide_owned_no_newline_markers(&lines, &mut hidden);

    let mut output = Vec::with_capacity(raw.len());
    let mut changed_lines = 0u32;
    let mut retained_changed_lines = 0u32;
    for (index, line) in lines.iter().enumerate() {
        if matches!(line.marker, Some(b'+' | b'-')) {
            changed_lines = changed_lines.saturating_add(1);
        }
        if let Some(fold) = folded_at.get(&index) {
            if matches!(line.marker, Some(b'+' | b'-')) {
                retained_changed_lines = retained_changed_lines.saturating_add(1);
            }
            output.extend_from_slice(fold);
            output.extend_from_slice(&line.eol);
            continue;
        }
        if hidden[index] {
            continue;
        }
        if matches!(line.marker, Some(b'+' | b'-')) {
            retained_changed_lines = retained_changed_lines.saturating_add(1);
        }
        if let Some(value) = replacements.get(&index) {
            output.extend_from_slice(value);
        } else {
            output.extend_from_slice(&line.text);
        }
        output.extend_from_slice(&line.eol);
    }
    Ok(CompileResult {
        reading_diff: output,
        summary: plan.summary.trim().to_string(),
        changed_lines,
        retained_changed_lines,
    })
}

fn validate_cross_chunk_move_retention(
    source_diff: &[u8],
    chunk_lines: &[SourceLine],
    hidden: &[bool],
) -> Result<(), ReadingDiffError> {
    let source_lines = parse(source_diff)?;
    let source_automatic = mandatory_import_mask(&source_lines);
    let mut removed = HashMap::<Vec<u8>, usize>::new();
    let mut added = HashMap::<Vec<u8>, usize>::new();
    let mut automatic_removed = HashMap::<Vec<u8>, bool>::new();
    let mut automatic_added = HashMap::<Vec<u8>, bool>::new();
    for (index, line) in source_lines.iter().enumerate() {
        let body = trim_ascii(source_body(line));
        if body.len() < 12 {
            continue;
        }
        match line.marker {
            Some(b'-') => {
                *removed.entry(body.to_vec()).or_default() += 1;
                automatic_removed.insert(body.to_vec(), source_automatic[index]);
            }
            Some(b'+') => {
                *added.entry(body.to_vec()).or_default() += 1;
                automatic_added.insert(body.to_vec(), source_automatic[index]);
            }
            _ => {}
        }
    }
    for (index, line) in chunk_lines.iter().enumerate() {
        if !hidden[index] || !matches!(line.marker, Some(b'+' | b'-')) {
            continue;
        }
        let body = trim_ascii(source_body(line));
        if removed.get(body) != Some(&1) || added.get(body) != Some(&1) {
            continue;
        }
        if automatic_removed.get(body) == Some(&true) && automatic_added.get(body) == Some(&true) {
            continue;
        }
        let counterpart = if line.marker == Some(b'-') {
            b'+'
        } else {
            b'-'
        };
        if !chunk_lines.iter().any(|candidate| {
            candidate.marker == Some(counterpart) && trim_ascii(source_body(candidate)) == body
        }) {
            return Err(ReadingDiffError::new(
                "Exact move rows whose counterpart is in another chunk must be retained.",
            ));
        }
    }
    Ok(())
}

pub(crate) fn validate_merged_move_symmetry(
    source: &[u8],
    reading_diff: &[u8],
) -> Result<(), ReadingDiffError> {
    let source_lines = parse(source)?;
    let mut removed = HashMap::<Vec<u8>, usize>::new();
    let mut added = HashMap::<Vec<u8>, usize>::new();
    for line in &source_lines {
        let body = trim_ascii(source_body(line));
        if body.len() < 12 {
            continue;
        }
        match line.marker {
            Some(b'-') => *removed.entry(body.to_vec()).or_default() += 1,
            Some(b'+') => *added.entry(body.to_vec()).or_default() += 1,
            _ => {}
        }
    }
    let mut retained_removed = HashSet::<Vec<u8>>::new();
    let mut retained_added = HashSet::<Vec<u8>>::new();
    for line in reading_diff.split(|byte| *byte == b'\n') {
        let Some(marker) = line.first() else {
            continue;
        };
        let body = trim_ascii(line.get(1..).unwrap_or_default());
        match marker {
            b'-' => {
                retained_removed.insert(body.to_vec());
            }
            b'+' => {
                retained_added.insert(body.to_vec());
            }
            _ => {}
        }
    }
    for (body, removed_count) in removed {
        if removed_count != 1 || added.get(&body) != Some(&1) {
            continue;
        }
        let retained_old = retained_removed.contains(&body);
        let retained_new = retained_added.contains(&body);
        if retained_old != retained_new {
            return Err(ReadingDiffError::new(
                "Exact move rows split across chunks must be retained or elided symmetrically.",
            ));
        }
    }
    Ok(())
}

fn validate_range(
    lines: &[SourceLine],
    range: LineRange,
    kind: &str,
    index: usize,
) -> Result<(), ReadingDiffError> {
    if range.start_line == 0
        || range.end_line == 0
        || range.start_line > range.end_line
        || range.end_line > lines.len()
    {
        return Err(ReadingDiffError::new(format!(
            "{kind}[{index}] has an invalid inclusive range {}-{} for a {} line diff.",
            range.start_line,
            range.end_line,
            lines.len()
        )));
    }
    for line_number in range.start_line..=range.end_line {
        if lines[line_number - 1].kind != LineKind::HunkSource {
            return Err(ReadingDiffError::new(format!(
                "{kind}[{index}] cannot change structural diff line {line_number}."
            )));
        }
    }
    Ok(())
}

fn claim_range(
    hidden: &mut [bool],
    ownership: &mut [Option<&'static str>],
    range: LineRange,
    kind: &'static str,
    index: usize,
    allow_automatic: bool,
) -> Result<(), ReadingDiffError> {
    for line_number in range.start_line..=range.end_line {
        let line = line_number - 1;
        if let Some(owner) = ownership[line] {
            if allow_automatic && owner == "automatic import elision" {
                continue;
            }
            return Err(ReadingDiffError::new(format!(
                "{kind}[{index}] overlaps {owner} at line {line_number}."
            )));
        }
        ownership[line] = Some(kind);
        hidden[line] = true;
    }
    Ok(())
}

fn validate_fold(
    lines: &[SourceLine],
    range: LineRange,
    index: usize,
) -> Result<(), ReadingDiffError> {
    let first = &lines[range.start_line - 1];
    for line_number in range.start_line..=range.end_line {
        let line = &lines[line_number - 1];
        if line.file_id != first.file_id
            || line.hunk_id != first.hunk_id
            || line.marker != first.marker
        {
            return Err(ReadingDiffError::new(format!(
                "fold[{index}] crosses a file, hunk, or diff marker boundary at line {line_number}."
            )));
        }
    }
    Ok(())
}

fn fold_line(line: &SourceLine) -> Vec<u8> {
    let body = source_body(line);
    let indent_end = body
        .iter()
        .position(|byte| !matches!(*byte, b' ' | b'\t'))
        .unwrap_or(body.len());
    let mut result = vec![line.marker.unwrap_or(b' ')];
    result.extend_from_slice(&body[..indent_end]);
    result.extend_from_slice(b"...");
    result
}

fn validate_replacements(
    lines: &[SourceLine],
    hidden: &[bool],
    replacements: &[LineReplacement],
) -> Result<HashMap<usize, Vec<u8>>, ReadingDiffError> {
    let mut result = HashMap::new();
    for (index, replacement) in replacements.iter().enumerate() {
        if replacement.line == 0 || replacement.line > lines.len() {
            return Err(ReadingDiffError::new(format!(
                "replace[{index}] line {} is outside the diff.",
                replacement.line
            )));
        }
        let line_index = replacement.line - 1;
        let line = &lines[line_index];
        if line.kind != LineKind::HunkSource {
            return Err(ReadingDiffError::new(format!(
                "replace[{index}] cannot change structural diff line {}.",
                replacement.line
            )));
        }
        if hidden[line_index] {
            return Err(ReadingDiffError::new(format!(
                "replace[{index}] targets hidden line {}.",
                replacement.line
            )));
        }
        if result.contains_key(&line_index) {
            return Err(ReadingDiffError::new(format!(
                "replace[{index}] overlaps an earlier replacement on line {}.",
                replacement.line
            )));
        }
        validate_projection(&replacement.old, &replacement.new, index)?;
        let body = std::str::from_utf8(source_body(line)).map_err(|_| {
            ReadingDiffError::new(format!(
                "replace[{index}] cannot address non-UTF-8 source line {}.",
                replacement.line
            ))
        })?;
        let matches = body.match_indices(&replacement.old).collect::<Vec<_>>();
        if matches.len() != 1 {
            return Err(ReadingDiffError::new(format!(
                "replace[{index}] old text must occur exactly once on line {}.",
                replacement.line
            )));
        }
        if file_is_python(lines, line)
            && changes_python_boundaries(&replacement.old, &replacement.new)
        {
            return Err(ReadingDiffError::new(format!(
                "replace[{index}] changes Python structural delimiters on line {}.",
                replacement.line
            )));
        }
        let at = matches[0].0;
        let mut rendered = vec![line.marker.unwrap_or(b' ')];
        rendered.extend_from_slice(&body.as_bytes()[..at]);
        rendered.extend_from_slice(replacement.new.as_bytes());
        rendered.extend_from_slice(&body.as_bytes()[at + replacement.old.len()..]);
        result.insert(line_index, rendered);
    }
    Ok(result)
}

fn validate_projection(old: &str, new: &str, index: usize) -> Result<(), ReadingDiffError> {
    if old.is_empty() || old.len() > 4096 || new.len() >= old.len() {
        return Err(ReadingDiffError::new(format!(
            "replace[{index}] must shorten a non-empty source span of at most 4096 bytes."
        )));
    }
    let normalized = new.replace('…', "...");
    if !normalized.contains("...") {
        return Err(ReadingDiffError::new(format!(
            "replace[{index}] must include an ellipsis placeholder."
        )));
    }
    let mut cursor = 0usize;
    for piece in normalized.split("...").filter(|piece| !piece.is_empty()) {
        let Some(relative) = old[cursor..].find(piece) else {
            return Err(ReadingDiffError::new(format!(
                "replace[{index}] invents or reorders text not projected from the source."
            )));
        };
        cursor += relative + piece.len();
    }
    Ok(())
}

fn validate_move_symmetry(lines: &[SourceLine], hidden: &[bool]) -> Result<(), ReadingDiffError> {
    let mut removed = HashMap::<Vec<u8>, Vec<usize>>::new();
    let mut added = HashMap::<Vec<u8>, Vec<usize>>::new();
    for (index, line) in lines.iter().enumerate() {
        let body = trim_ascii(source_body(line));
        if body.len() < 12 {
            continue;
        }
        match line.marker {
            Some(b'-') => removed.entry(body.to_vec()).or_default().push(index),
            Some(b'+') => added.entry(body.to_vec()).or_default().push(index),
            _ => {}
        }
    }
    for (body, old_lines) in removed {
        let Some(new_lines) = added.get(&body) else {
            continue;
        };
        if old_lines.len() == 1
            && new_lines.len() == 1
            && hidden[old_lines[0]] != hidden[new_lines[0]]
        {
            return Err(ReadingDiffError::new(format!(
                "Exact move rows {} and {} must be retained or elided symmetrically.",
                old_lines[0] + 1,
                new_lines[0] + 1
            )));
        }
    }
    Ok(())
}

fn protect_python_structure(
    lines: &[SourceLine],
    range: LineRange,
    kind: &str,
    index: usize,
) -> Result<(), ReadingDiffError> {
    let mut balances = [0i32; 3];
    let mut triples = [0usize; 2];
    for line_number in range.start_line..=range.end_line {
        let line = &lines[line_number - 1];
        if !file_is_python(lines, line) {
            continue;
        }
        let body = String::from_utf8_lossy(source_body(line));
        let trimmed = body.trim_start();
        if trimmed.starts_with('@') || trimmed.trim_end().ends_with(':') {
            return Err(ReadingDiffError::new(format!(
                "{kind}[{index}] hides a Python decorator or suite owner on line {line_number}."
            )));
        }
        balances[0] += count_byte(body.as_bytes(), b'(') - count_byte(body.as_bytes(), b')');
        balances[1] += count_byte(body.as_bytes(), b'[') - count_byte(body.as_bytes(), b']');
        balances[2] += count_byte(body.as_bytes(), b'{') - count_byte(body.as_bytes(), b'}');
        triples[0] += body.matches("'''").count();
        triples[1] += body.matches("\"\"\"").count();
    }
    if balances != [0, 0, 0] || triples.iter().any(|count| count % 2 != 0) {
        return Err(ReadingDiffError::new(format!(
            "{kind}[{index}] crosses Python expression or string boundaries."
        )));
    }
    Ok(())
}

fn file_is_python(lines: &[SourceLine], line: &SourceLine) -> bool {
    let Some(file_id) = line.file_id else {
        return false;
    };
    lines.iter().any(|candidate| {
        candidate.file_id == Some(file_id)
            && candidate.text.starts_with(b"diff --git ")
            && String::from_utf8_lossy(&candidate.text)
                .split_whitespace()
                .any(|path| {
                    let path = path.trim_matches('"');
                    path.ends_with(".py") || path.ends_with(".pyi")
                })
    })
}

fn changes_python_boundaries(old: &str, new: &str) -> bool {
    ["(", ")", "[", "]", "{", "}", "'''", "\"\"\""]
        .iter()
        .any(|token| old.matches(token).count() != new.matches(token).count())
}

fn hide_owned_no_newline_markers(lines: &[SourceLine], hidden: &mut [bool]) {
    for index in 1..lines.len() {
        if lines[index].kind == LineKind::NoNewline && hidden[index - 1] {
            hidden[index] = true;
        }
    }
}

fn count_byte(value: &[u8], needle: u8) -> i32 {
    value.iter().filter(|byte| **byte == needle).count() as i32
}

fn trim_ascii(value: &[u8]) -> &[u8] {
    let start = value
        .iter()
        .position(|byte| !byte.is_ascii_whitespace())
        .unwrap_or(value.len());
    let end = value
        .iter()
        .rposition(|byte| !byte.is_ascii_whitespace())
        .map_or(start, |index| index + 1);
    &value[start..end]
}
