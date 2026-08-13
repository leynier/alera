// SPDX-License-Identifier: Apache-2.0
// Ported and modified from Meat revision f39f41dfe7b5b37a12b35fdfbaecc7e779855bd3.

use std::collections::{HashMap, HashSet};

use super::diff::{parse, source_body, SourceLine};
use super::imports::mandatory_import_mask;
use super::ReadingDiffError;

pub(crate) fn validate_cross_chunk_move_retention(
    source_diff: &[u8],
    chunk_lines: &[SourceLine],
    hidden: &[bool],
    replacements: &HashMap<usize, Vec<u8>>,
) -> Result<(), ReadingDiffError> {
    let source_lines = parse(source_diff)?;
    let mut source_automatic = mandatory_import_mask(&source_lines);
    normalize_automatic_move_mask(&source_lines, &mut source_automatic);
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
        if !matches!(line.marker, Some(b'+' | b'-')) {
            continue;
        }
        let body = trim_ascii(source_body(line));
        if removed.get(body) != Some(&1) || added.get(body) != Some(&1) {
            continue;
        }
        if replacements.contains_key(&index) {
            return Err(ReadingDiffError::new(
                "replace cannot abbreviate an exact move row.",
            ));
        }
        if !hidden[index] {
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

pub(crate) fn validate_move_symmetry(
    lines: &[SourceLine],
    hidden: &[bool],
) -> Result<(), ReadingDiffError> {
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

pub(crate) fn normalize_automatic_move_mask(lines: &[SourceLine], hidden: &mut [bool]) {
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
            && (hidden[old_lines[0]] || hidden[new_lines[0]])
        {
            hidden[old_lines[0]] = true;
            hidden[new_lines[0]] = true;
        }
    }
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
