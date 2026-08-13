// SPDX-License-Identifier: Apache-2.0
// Ported and modified from Meat revision f39f41dfe7b5b37a12b35fdfbaecc7e779855bd3.

use super::compiler::{validate_merged_move_symmetry, CompileResult};
use super::diff::{numbered, parse};
use super::{ReadingDiffError, RUBRIC_VERSION, SCHEMA_VERSION};

pub const DEFAULT_MAX_CHUNK_BYTES: usize = 160 * 1024;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ReadingDiffChunk {
    pub index: u32,
    pub raw_diff: Vec<u8>,
    pub numbered_diff: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PreparedDiff {
    pub raw_bytes: u64,
    pub schema_version: u32,
    pub rubric_version: String,
    pub chunks: Vec<ReadingDiffChunk>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CompiledChunk {
    pub index: u32,
    pub result: CompileResult,
}

pub fn prepare(
    raw: &[u8],
    max_chunk_bytes: Option<usize>,
) -> Result<PreparedDiff, ReadingDiffError> {
    parse(raw)?;
    if raw.is_empty() {
        return Err(ReadingDiffError::new("The diff is empty."));
    }
    let limit = max_chunk_bytes.unwrap_or(DEFAULT_MAX_CHUNK_BYTES).max(4096);
    let sections = file_sections(raw);
    let mut raw_chunks = Vec::<Vec<u8>>::new();
    let mut current = Vec::<u8>::new();
    for section in sections {
        if section.len() > limit {
            if !current.is_empty() {
                raw_chunks.push(std::mem::take(&mut current));
            }
            raw_chunks.extend(split_file_at_hunks(&section, limit)?);
            continue;
        }
        if !current.is_empty() && current.len() + section.len() > limit {
            raw_chunks.push(std::mem::take(&mut current));
        }
        current.extend_from_slice(&section);
    }
    if !current.is_empty() {
        raw_chunks.push(current);
    }
    let chunks = raw_chunks
        .into_iter()
        .enumerate()
        .map(|(index, raw_diff)| {
            Ok(ReadingDiffChunk {
                index: index as u32,
                numbered_diff: numbered(&raw_diff)?,
                raw_diff,
            })
        })
        .collect::<Result<Vec<_>, ReadingDiffError>>()?;
    Ok(PreparedDiff {
        raw_bytes: raw.len() as u64,
        schema_version: SCHEMA_VERSION,
        rubric_version: RUBRIC_VERSION.to_string(),
        chunks,
    })
}

pub fn merge_chunks(
    mut chunks: Vec<CompiledChunk>,
    source_diff: &[u8],
) -> Result<CompileResult, ReadingDiffError> {
    if chunks.is_empty() {
        return Err(ReadingDiffError::new(
            "No reading diff chunks were compiled.",
        ));
    }
    chunks.sort_by_key(|chunk| chunk.index);
    for (expected, chunk) in chunks.iter().enumerate() {
        if chunk.index != expected as u32 {
            return Err(ReadingDiffError::new(
                "Reading diff chunks are missing or out of sequence.",
            ));
        }
    }
    let mut reading_diff = Vec::new();
    let mut summaries = Vec::new();
    let mut changed_lines = 0u32;
    let mut retained_changed_lines = 0u32;
    for chunk in chunks {
        reading_diff.extend_from_slice(&chunk.result.reading_diff);
        if !reading_diff.ends_with(b"\n") {
            reading_diff.push(b'\n');
        }
        summaries.push(chunk.result.summary);
        changed_lines = changed_lines.saturating_add(chunk.result.changed_lines);
        retained_changed_lines =
            retained_changed_lines.saturating_add(chunk.result.retained_changed_lines);
    }
    summaries.dedup();
    validate_merged_move_symmetry(source_diff, &reading_diff)?;
    Ok(CompileResult {
        reading_diff,
        summary: summaries.join(" "),
        changed_lines,
        retained_changed_lines,
    })
}

fn file_sections(raw: &[u8]) -> Vec<Vec<u8>> {
    let mut starts = vec![0usize];
    for index in 1..raw.len() {
        if raw[index..].starts_with(b"diff --git ") && raw[index - 1] == b'\n' {
            starts.push(index);
        }
    }
    starts.push(raw.len());
    starts
        .windows(2)
        .map(|window| raw[window[0]..window[1]].to_vec())
        .filter(|section| !section.is_empty())
        .collect()
}

fn split_file_at_hunks(section: &[u8], limit: usize) -> Result<Vec<Vec<u8>>, ReadingDiffError> {
    let hunk_starts = line_starts_with(section, b"@@ ");
    if hunk_starts.len() < 2 {
        return Err(ReadingDiffError::new(format!(
            "A single diff hunk is {} bytes, above the safe {} byte agent prompt limit.",
            section.len(),
            limit
        )));
    }
    let preamble = &section[..hunk_starts[0]];
    let mut result = Vec::new();
    for (position, start) in hunk_starts.iter().copied().enumerate() {
        let end = hunk_starts
            .get(position + 1)
            .copied()
            .unwrap_or(section.len());
        let hunk = &section[start..end];
        if preamble.len() + hunk.len() > limit {
            return Err(ReadingDiffError::new(format!(
                "A single diff hunk is {} bytes, above the safe {} byte agent prompt limit.",
                hunk.len(),
                limit
            )));
        }
        let mut chunk = preamble.to_vec();
        chunk.extend_from_slice(hunk);
        result.push(chunk);
    }
    Ok(result)
}

fn line_starts_with(raw: &[u8], prefix: &[u8]) -> Vec<usize> {
    let mut result = Vec::new();
    if raw.starts_with(prefix) {
        result.push(0);
    }
    for index in 1..raw.len() {
        if raw[index - 1] == b'\n' && raw[index..].starts_with(prefix) {
            result.push(index);
        }
    }
    result
}
