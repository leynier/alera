//! Reads issues from the forge that hosts them, for workspaces linked to an
//! issue and for `alera issue show`. Every provider goes through that forge's
//! own CLI (`gh`, `glab`, `az boards`), so authentication stays with the CLI
//! and Alera never holds a forge token.

mod azure_devops_issue_provider;
mod forge_cli_failure;
mod forge_cli_runner;
mod github_issue_provider;
mod gitlab_issue_provider;
mod issue_details;
mod issue_fetch_error;
mod issue_provider_registry;
mod issue_reference;

#[cfg(test)]
pub(crate) use forge_cli_failure::fake::FakeForgeCliRunner;
pub use forge_cli_runner::{ForgeCliOutput, ForgeCliRunner, SystemForgeCliRunner};
pub use issue_details::{IssueDetails, IssueState};
pub use issue_fetch_error::IssueFetchError;
pub use issue_provider_registry::{fetch_issue, fetch_issue_url};
pub use issue_reference::{parse_issue_reference, IssueProvider, IssueReference};
