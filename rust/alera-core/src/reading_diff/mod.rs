// Ported and modified from Meat at f39f41dfe7b5b37a12b35fdfbaecc7e779855bd3.
// The derived reading-diff core remains available under Apache-2.0.

mod chunk;
mod compiler;
mod diff;
mod plan;
mod prompt;

pub use chunk::{merge_chunks, prepare, CompiledChunk, PreparedDiff, ReadingDiffChunk};
pub use compiler::{compile, CompileResult};
pub use plan::Plan;
pub use prompt::{plan_schema, RUBRIC_VERSION, SCHEMA_VERSION};

use std::fmt::{Display, Formatter};

#[cfg(test)]
mod tests;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ReadingDiffError {
    pub message: String,
}

impl ReadingDiffError {
    pub(crate) fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl Display for ReadingDiffError {
    fn fmt(&self, formatter: &mut Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl std::error::Error for ReadingDiffError {}
