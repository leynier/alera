use super::{IdArgs, OutputArgs, RuntimeDirArgs};
use clap::{ArgGroup, Args, Subcommand};

#[derive(Debug, Args)]
pub struct AutomationCommand {
    #[command(flatten)]
    pub runtime: RuntimeDirArgs,
    #[command(flatten)]
    pub output: OutputArgs,
    #[command(subcommand)]
    pub action: AutomationAction,
}

#[derive(Debug, Subcommand)]
pub enum AutomationAction {
    /// List automations, optionally including the trash.
    List(AutomationListArgs),
    /// Show one automation with its recent runs and audit history.
    Show(IdArgs),
    /// Create an automation from a JSON definition file or stdin.
    Create(AutomationDefinitionFileArgs),
    /// Edit an automation from a JSON definition file or stdin.
    Edit(AutomationDefinitionFileArgs),
    /// Approve an exact automation revision for activation.
    Approve(AutomationRevisionArgs),
    /// Pause an active automation.
    Pause(AutomationStateArgs),
    /// Resume a paused automation.
    Resume(AutomationStateArgs),
    /// Move an automation to recoverable trash.
    Trash(AutomationStateArgs),
    /// Restore a trashed automation as a draft.
    Restore(AutomationStateArgs),
    /// Permanently purge automations trashed for at least 30 days.
    Purge,
    /// Start one run immediately.
    RunNow(AutomationRunNowArgs),
    /// List automation runs.
    Runs(AutomationRunsArgs),
    /// Show one run and its automation definition.
    RunShow(IdArgs),
    /// Cancel one non-final run.
    Cancel(AutomationRunIdArgs),
    /// Show the context and lifecycle contract for a run.
    Context(AutomationRunIdArgs),
    /// Record a lifecycle heartbeat for a run.
    Heartbeat(AutomationRunIdArgs),
    /// Mark a run as waiting for user input or resume it.
    Wait(AutomationWaitArgs),
    /// Extend the absolute deadline of a waiting run.
    Extend(AutomationExtendArgs),
    /// Complete a run with a required summary.
    Complete(AutomationCompleteArgs),
    /// List or upsert prompt templates.
    Templates(AutomationCatalogFileArgs),
    /// List or upsert tags and assignments.
    Tags(AutomationCatalogFileArgs),
    /// Import a runtime-local automation catalog.
    Import(AutomationImportArgs),
    /// Export a runtime-local automation catalog.
    Export(AutomationExportArgs),
    /// Show or update an agent/project automation policy.
    Policy(AutomationPolicyArgs),
}

#[derive(Debug, Args)]
pub struct AutomationListArgs {
    /// Include automations in recoverable trash.
    #[arg(long)]
    pub include_trashed: bool,
    #[arg(long)]
    pub state: Option<String>,
    #[arg(long = "project-id")]
    pub project_id: Option<String>,
    #[arg(long = "profile-id")]
    pub profile_id: Option<String>,
    #[arg(long)]
    pub tag: Option<String>,
    #[arg(long)]
    pub search: Option<String>,
}

#[derive(Debug, Args)]
pub struct AutomationDefinitionFileArgs {
    /// JSON file path, or - to read the definition from stdin.
    #[arg(long = "file", alias = "definition-file")]
    pub file: String,
}

#[derive(Debug, Args)]
pub struct AutomationRevisionArgs {
    #[arg(long)]
    pub id: String,
    #[arg(long)]
    pub revision: i64,
}

#[derive(Debug, Args)]
pub struct AutomationStateArgs {
    #[arg(long)]
    pub id: String,
    #[arg(long)]
    pub reason: Option<String>,
    /// Required when pausing with an active run.
    #[arg(long = "active-runs", value_parser = ["continue-active", "cancel-active"])]
    pub active_runs: Option<String>,
}

#[derive(Debug, Args)]
#[command(group(
    ArgGroup::new("precheck-choice")
        .required(true)
        .args(["precheck", "skip_precheck"])
))]
pub struct AutomationRunNowArgs {
    #[arg(long)]
    pub id: String,
    /// Run the configured precheck before dispatching.
    #[arg(long, conflicts_with = "skip_precheck")]
    pub precheck: bool,
    /// Explicitly skip the configured precheck.
    #[arg(long = "skip-precheck", conflicts_with = "precheck")]
    pub skip_precheck: bool,
    /// Explicit overlap behavior: skip, queue, runLatestOnce, or forceParallel.
    #[arg(
        long,
        required = true,
        value_parser = ["skip", "queue", "runLatestOnce", "forceParallel"]
    )]
    pub overlap: Option<String>,
    /// Run a draft as an audited human test.
    #[arg(long = "draft-test")]
    pub draft_test: bool,
    /// Exact approved revision to use for a human Run Now exception.
    #[arg(long)]
    pub revision: Option<i64>,
    #[command(flatten)]
    pub target: AutomationTargetArgs,
}

#[derive(Debug, Args)]
pub struct AutomationRunsArgs {
    #[arg(long = "automation-id")]
    pub automation_id: Option<String>,
    #[arg(long, default_value_t = 100)]
    pub limit: i64,
}

#[derive(Debug, Args)]
pub struct AutomationRunIdArgs {
    #[arg(long = "run")]
    pub run_id: String,
    #[command(flatten)]
    pub target: AutomationTargetArgs,
}

#[derive(Debug, Args, Clone, Default)]
pub struct AutomationTargetArgs {
    #[arg(long = "workspace-id")]
    pub workspace_id: Option<String>,
    #[arg(long = "tab-id")]
    pub tab_id: Option<String>,
    #[arg(long = "session-id")]
    pub session_id: Option<String>,
    #[arg(long = "profile-id")]
    pub profile_id: Option<String>,
    #[arg(long = "conversation-id")]
    pub conversation_id: Option<String>,
    #[arg(long = "terminal-handle")]
    pub terminal_handle: Option<String>,
}

#[derive(Debug, Args)]
pub struct AutomationWaitArgs {
    #[arg(long = "run")]
    pub run_id: String,
    #[arg(long)]
    pub resume: bool,
    #[command(flatten)]
    pub target: AutomationTargetArgs,
}

#[derive(Debug, Args)]
pub struct AutomationExtendArgs {
    #[arg(long = "run")]
    pub run_id: String,
    #[arg(long, conflicts_with = "seconds")]
    pub until: Option<String>,
    #[arg(long, conflicts_with = "until")]
    pub seconds: Option<i64>,
    #[command(flatten)]
    pub target: AutomationTargetArgs,
}

#[derive(Debug, Args)]
pub struct AutomationCompleteArgs {
    #[arg(long = "run")]
    pub run_id: String,
    #[arg(long, value_parser = ["success", "failure", "blocked"])]
    pub status: String,
    #[arg(long)]
    pub summary: String,
    #[arg(long)]
    pub error: Option<String>,
    #[command(flatten)]
    pub target: AutomationTargetArgs,
}

#[derive(Debug, Args)]
pub struct AutomationCatalogFileArgs {
    /// Optional JSON file containing a template/tag object to upsert.
    #[arg(long = "file", alias = "object-file")]
    pub file: Option<String>,
}

#[derive(Debug, Args)]
pub struct AutomationImportArgs {
    /// JSON catalog file, or - to read the catalog from stdin.
    #[arg(long = "file")]
    pub file: String,
    /// Explicit source-id=target-id mappings, repeatable.
    #[arg(long = "remap", value_parser = parse_remap)]
    pub remap: Vec<(String, String)>,
}

#[derive(Debug, Args)]
pub struct AutomationExportArgs {
    /// Optional path to write the exported catalog.
    #[arg(long = "file")]
    pub file: Option<String>,
}

#[derive(Debug, Args)]
pub struct AutomationPolicyArgs {
    /// Policy kind: show, agent, or project.
    #[arg(long, default_value = "show", value_parser = ["show", "agent", "project"])]
    pub kind: String,
    #[arg(long = "profile-id")]
    pub profile_id: Option<String>,
    #[arg(long = "project-id")]
    pub project_id: Option<String>,
    /// JSON policy file to save instead of reading the current policy.
    #[arg(long = "file")]
    pub file: Option<String>,
}

fn parse_remap(value: &str) -> Result<(String, String), String> {
    value
        .split_once('=')
        .map(|(source, target)| (source.to_string(), target.to_string()))
        .filter(|(source, target)| !source.is_empty() && !target.is_empty())
        .ok_or_else(|| "remap must use source-id=target-id".to_string())
}

#[cfg(test)]
mod tests {
    use clap::Parser;

    use super::parse_remap;
    use crate::cli::{AutomationAction, Cli, Command};

    #[test]
    fn remap_parser_requires_two_nonblank_ids() {
        assert_eq!(
            parse_remap("source=target").unwrap(),
            ("source".into(), "target".into())
        );
        assert!(parse_remap("source=").is_err());
        assert!(parse_remap("=target").is_err());
        assert!(parse_remap("source").is_err());
    }

    #[test]
    fn run_now_requires_explicit_precheck_and_overlap() {
        let valid = Cli::try_parse_from([
            "alera",
            "automation",
            "run-now",
            "--id",
            "automation",
            "--skip-precheck",
            "--overlap",
            "runLatestOnce",
        ])
        .unwrap();
        assert!(matches!(
            valid.command,
            Command::Automation(crate::cli::AutomationCommand {
                action: AutomationAction::RunNow(_),
                ..
            })
        ));
        assert!(Cli::try_parse_from([
            "alera",
            "automation",
            "run-now",
            "--id",
            "automation",
            "--overlap",
            "queue",
        ])
        .is_err());
        assert!(Cli::try_parse_from([
            "alera",
            "automation",
            "run-now",
            "--id",
            "automation",
            "--precheck",
            "--overlap",
            "skip",
        ])
        .is_ok());
    }

    #[test]
    fn complete_rejects_statuses_outside_final_contract() {
        for status in ["success", "failure", "blocked"] {
            assert!(Cli::try_parse_from([
                "alera",
                "automation",
                "complete",
                "--run",
                "run",
                "--status",
                status,
                "--summary",
                "done",
            ])
            .is_ok());
        }
        assert!(Cli::try_parse_from([
            "alera",
            "automation",
            "complete",
            "--run",
            "run",
            "--status",
            "timeout",
            "--summary",
            "done",
        ])
        .is_err());
    }
}
