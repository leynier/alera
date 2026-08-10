use alera_core::reading_diff;

use super::git::{GitChangeArea, GitError};

pub struct ReadingDiffChunk {
    pub index: u32,
    pub raw_diff: Vec<u8>,
    pub numbered_diff: String,
}

pub struct ReadingDiffPreparation {
    pub raw_bytes: u64,
    pub schema_version: u32,
    pub rubric_version: String,
    pub plan_schema: String,
    pub chunks: Vec<ReadingDiffChunk>,
}

pub struct ReadingDiffCompileResult {
    pub reading_diff: Vec<u8>,
    pub summary: String,
    pub changed_lines: u32,
    pub retained_changed_lines: u32,
}

pub struct ReadingDiffCompiledChunk {
    pub index: u32,
    pub reading_diff: Vec<u8>,
    pub summary: String,
    pub changed_lines: u32,
    pub retained_changed_lines: u32,
}

#[derive(Debug)]
pub struct ReadingDiffError {
    pub message: String,
}

impl From<reading_diff::ReadingDiffError> for ReadingDiffError {
    fn from(error: reading_diff::ReadingDiffError) -> Self {
        Self {
            message: error.message,
        }
    }
}

pub fn git_reading_diff_patch(
    path: String,
    file_path: Option<String>,
    area: Option<GitChangeArea>,
    commit_oid: Option<String>,
    parent_oid: Option<String>,
    base_ref: Option<String>,
) -> Result<Vec<u8>, GitError> {
    super::git::git_diff_impl::git_reading_diff_patch::git_reading_diff_patch(
        path, file_path, area, commit_oid, parent_oid, base_ref,
    )
}

pub fn prepare_reading_diff(diff: Vec<u8>) -> Result<ReadingDiffPreparation, ReadingDiffError> {
    let prepared = reading_diff::prepare(&diff, None)?;
    Ok(ReadingDiffPreparation {
        raw_bytes: prepared.raw_bytes,
        schema_version: prepared.schema_version,
        rubric_version: prepared.rubric_version,
        plan_schema: reading_diff::plan_schema(),
        chunks: prepared
            .chunks
            .into_iter()
            .map(|chunk| ReadingDiffChunk {
                index: chunk.index,
                raw_diff: chunk.raw_diff,
                numbered_diff: chunk.numbered_diff,
            })
            .collect(),
    })
}

pub fn compile_reading_diff_plan(
    diff: Vec<u8>,
    plan_json: String,
) -> Result<ReadingDiffCompileResult, ReadingDiffError> {
    reading_diff::compile(&diff, &plan_json)
        .map(ReadingDiffCompileResult::from)
        .map_err(Into::into)
}

pub fn merge_reading_diff_chunks(
    chunks: Vec<ReadingDiffCompiledChunk>,
) -> Result<ReadingDiffCompileResult, ReadingDiffError> {
    let chunks = chunks
        .into_iter()
        .map(|chunk| reading_diff::CompiledChunk {
            index: chunk.index,
            result: reading_diff::CompileResult {
                reading_diff: chunk.reading_diff,
                summary: chunk.summary,
                changed_lines: chunk.changed_lines,
                retained_changed_lines: chunk.retained_changed_lines,
            },
        })
        .collect();
    reading_diff::merge_chunks(chunks)
        .map(ReadingDiffCompileResult::from)
        .map_err(Into::into)
}

impl From<reading_diff::CompileResult> for ReadingDiffCompileResult {
    fn from(result: reading_diff::CompileResult) -> Self {
        Self {
            reading_diff: result.reading_diff,
            summary: result.summary,
            changed_lines: result.changed_lines,
            retained_changed_lines: result.retained_changed_lines,
        }
    }
}
