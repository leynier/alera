//! Names of the Git resources a run owns. The v3 store starts runs from
//! scratch, so nothing reads the older `workflow` prefixes.

pub const RUN_BRANCH_PREFIX: &str = "alera/runs/";
pub const RUN_RESOURCE_REF_PREFIX: &str = "refs/alera/run-resources/";
pub const RUN_INTEGRATION_REF_PREFIX: &str = "refs/alera/run-integrations/";
pub const RUN_CLEANUP_REF_PREFIX: &str = "refs/alera/run-cleanup/";

/// Short branch name, as stored on the workspace record.
pub fn run_branch_name(id: &str) -> String {
    format!("{RUN_BRANCH_PREFIX}{id}")
}

/// Fully qualified branch reference.
pub fn run_branch_ref(id: &str) -> String {
    format!("refs/heads/{RUN_BRANCH_PREFIX}{id}")
}
