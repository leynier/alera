use serde::Deserialize;

use super::ReadingDiffError;

#[derive(Clone, Debug, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct Plan {
    pub version: u32,
    pub remove: Vec<LineRange>,
    pub replace: Vec<LineReplacement>,
    pub fold: Vec<LineRange>,
    pub summary: String,
}

#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct LineRange {
    pub start_line: usize,
    pub end_line: usize,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct LineReplacement {
    pub line: usize,
    pub old: String,
    pub new: String,
}

impl Plan {
    pub fn parse(json: &str) -> Result<Self, ReadingDiffError> {
        let plan: Self = serde_json::from_str(json).map_err(|error| {
            ReadingDiffError::new(format!("Invalid reading diff plan: {error}"))
        })?;
        if plan.version != super::SCHEMA_VERSION {
            return Err(ReadingDiffError::new(format!(
                "Unsupported reading diff plan version {}; expected {}.",
                plan.version,
                super::SCHEMA_VERSION
            )));
        }
        let summary = plan.summary.trim();
        if summary.is_empty() {
            return Err(ReadingDiffError::new(
                "The reading diff summary is required.",
            ));
        }
        if summary.contains(['\r', '\n']) || summary.len() > 500 {
            return Err(ReadingDiffError::new(
                "The reading diff summary must be one line of at most 500 bytes.",
            ));
        }
        Ok(plan)
    }
}
