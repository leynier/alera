use super::{IdArgs, OutputArgs, RuntimeDirArgs};
use clap::{Args, Subcommand};

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
    /// Create an automation with flags or a JSON definition file.
    Create(AutomationDefinitionFileArgs),
    /// Validate a partial draft without saving it.
    Readiness(AutomationDefinitionFileArgs),
    /// Preview the next occurrences from cron or a one-time date.
    PreviewSchedule(AutomationDefinitionFileArgs),
    /// Patch an automation with flags or a JSON definition file.
    Edit(AutomationDefinitionFileArgs),
    /// Deprecated alias for resume. No approval is required.
    #[command(hide = true)]
    Approve(AutomationRevisionArgs),
    /// Pause an active automation.
    Pause(AutomationStateArgs),
    /// Resume a paused automation.
    Resume(AutomationStateArgs),
    /// Move an automation to recoverable trash.
    Trash(AutomationStateArgs),
    /// Restore a trashed automation paused, or completed if previously completed.
    Restore(AutomationStateArgs),
    /// Permanently purge automations trashed for at least 30 days.
    Purge,
    /// Start one run immediately.
    RunNow(AutomationRunNowArgs),
    /// List automation runs.
    Runs(AutomationRunsArgs),
    /// Show one run and its automation definition.
    RunShow(IdArgs),
    /// Create a new automation from an existing one, as the Clone action does.
    Clone(AutomationCloneArgs),
    /// Take over the terminal of a run so the automation stops driving it.
    TakeOver(AutomationTakeOverArgs),
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
    pub search: Option<String>,
    #[arg(long)]
    pub workspace_id: Option<String>,
    #[arg(long)]
    pub section_id: Option<String>,
    #[arg(long)]
    pub host_id: Option<String>,
    #[arg(long)]
    pub bucket: Option<String>,
}

#[derive(Debug, Args)]
pub struct AutomationDefinitionFileArgs {
    /// JSON file path, or - to read the definition from stdin.
    #[arg(long = "file", alias = "definition-file")]
    pub file: Option<String>,
    #[arg(long)]
    pub id: Option<String>,
    #[arg(long)]
    pub name: Option<String>,
    #[arg(long, conflicts_with = "prompt_file")]
    pub prompt: Option<String>,
    #[arg(long)]
    pub prompt_file: Option<String>,
    #[arg(long, conflicts_with = "at")]
    pub cron: Option<String>,
    #[arg(long)]
    pub at: Option<String>,
    #[arg(long)]
    pub timezone: Option<String>,
    /// Required for flag-based creation; never inferred from context.
    /// `managed-workspace` and `project-worktree` are older names for
    /// `worktree`.
    #[arg(long, value_parser = ["fresh-tab", "existing-tab", "worktree", "managed-workspace", "project-worktree", "project-checkout"])]
    pub target: Option<String>,
    #[arg(long)]
    pub workspace_id: Option<String>,
    #[arg(long)]
    pub project_id: Option<String>,
    #[arg(long)]
    pub host_id: Option<String>,
    #[arg(long)]
    pub profile_id: Option<String>,
    #[arg(long)]
    pub tab_id: Option<String>,
    #[arg(long)]
    pub conversation_id: Option<String>,
    #[arg(long)]
    pub source_branch: Option<String>,
    #[arg(long)]
    pub origin_workspace_id: Option<String>,
    #[arg(long)]
    pub draft: bool,
    #[arg(long)]
    pub dry_run: bool,
    #[arg(long)]
    pub request_key: Option<String>,
    #[arg(long)]
    pub expected_revision: Option<i64>,
}

#[derive(Debug, Args)]
pub struct AutomationRevisionArgs {
    #[arg(long)]
    pub id: String,
    #[arg(long)]
    pub revision: Option<i64>,
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
        value_parser = ["skip", "queue", "runLatestOnce", "forceParallel"]
    )]
    pub overlap: Option<String>,
    /// Deprecated compatibility option and ignored; every technically valid state can run.
    #[arg(long = "draft-test", hide = true)]
    pub draft_test: bool,
    /// Optional expected revision to reject a stale Run Now request.
    #[arg(long)]
    pub revision: Option<i64>,
    #[arg(long)]
    pub continue_from_run: Option<String>,
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
    /// Use the target identity the run recorded, as the Alera app does.
    #[arg(long = "use-run-identity")]
    pub use_run_identity: bool,
    #[command(flatten)]
    pub target: AutomationTargetArgs,
}

#[derive(Debug, Args, Clone, Default)]
pub struct AutomationTargetArgs {
    #[arg(long)]
    pub attempt_id: Option<String>,
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
    /// Use the target identity the run recorded, as the Alera app does.
    #[arg(long = "use-run-identity")]
    pub use_run_identity: bool,
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
    /// Use the target identity the run recorded, as the Alera app does.
    #[arg(long = "use-run-identity")]
    pub use_run_identity: bool,
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
pub struct AutomationCloneArgs {
    #[arg(long)]
    pub id: String,
    /// Name of the copy (default: the original name followed by Copy).
    #[arg(long)]
    pub name: Option<String>,
    /// Save the copy as a draft instead of activating it.
    #[arg(long)]
    pub draft: bool,
    #[arg(long)]
    pub request_key: Option<String>,
}

#[derive(Debug, Args)]
pub struct AutomationTakeOverArgs {
    #[arg(long = "run")]
    pub run_id: String,
}

#[cfg(test)]
mod tests {
    use clap::Parser;

    use crate::cli::{AutomationAction, Cli, Command};

    #[test]
    fn run_now_defaults_to_definition_choices() {
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
        .is_ok());
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

    #[test]
    fn retired_catalog_and_policy_subcommands_are_gone() {
        for action in ["templates", "tags", "import", "export", "policy"] {
            assert!(
                Cli::try_parse_from(["alera", "automation", action]).is_err(),
                "{action} still parses"
            );
        }
        assert!(Cli::try_parse_from(["alera", "automation", "list", "--tag", "t"]).is_err());
    }

    #[test]
    fn approve_and_draft_test_still_parse_for_older_scripts() {
        assert!(Cli::try_parse_from(["alera", "automation", "approve", "--id", "a"]).is_ok());
        assert!(Cli::try_parse_from([
            "alera",
            "automation",
            "run-now",
            "--id",
            "a",
            "--draft-test"
        ])
        .is_ok());
    }
}

#[derive(Debug, Args)]
pub struct AutomationHostArgs {
    /// Runtime profile directory used by the automation host.
    #[arg(long = "runtime-dir", value_name = "path")]
    pub runtime_dir: String,
}
