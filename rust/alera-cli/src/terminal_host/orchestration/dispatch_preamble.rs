pub struct BaseDrift {
    pub base: String,
    pub behind: u64,
    pub recent_subjects: Vec<String>,
}

pub struct PreambleParams<'a> {
    pub task_id: &'a str,
    /// Completion and heartbeat commands attribute activity to a specific
    /// dispatch context (not just a task): a retried task has multiple
    /// dispatch contexts, and keying lifecycle operations on dispatchId
    /// prevents stale messages from a previously-failed dispatch from
    /// completing or refreshing the retry.
    pub dispatch_id: &'a str,
    pub task_spec: &'a str,
    pub coordinator_handle: &'a str,
    /// Populated by the coordinator's dispatch pre-flight only when the
    /// target worktree is behind its tracking remote. Callers must NOT
    /// pre-populate this with empty data; the drift section is a
    /// loud-but-rare signal.
    pub base_drift: Option<&'a BaseDrift>,
    /// Appended when the task had a resolved decision gate: the worker sees
    /// the human's answer from line 1 of the re-dispatch.
    pub gate_resolution: Option<&'a GateResolution>,
    /// Controls post-completion instructions. Inject paths always use
    /// prompt-returning agents; bare-shell is for dry-run paste only.
    pub worker_kind: WorkerKind,
}

pub struct GateResolution {
    pub question: String,
    pub resolution: String,
}

/// Distinguishes prompt-returning agent workers (Claude, Codex, …) from bare
/// shell workers. After completion, agents should idle for re-dispatch;
/// bare shells have no reusable prompt and should exit.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum WorkerKind {
    #[default]
    PromptReturningAgent,
    /// Used when a human pastes a preamble into a bare shell (dry-run path).
    BareShell,
}

/// The dispatch preamble teaches agents Alera's CLI commands for structured
/// communication. Behavioral rules live as inline comments above the relevant
/// CLI example, not as a separate prose block - LLM readers anchor on
/// examples and skim trailing prose, so rules must land at the point of use.
pub fn build_dispatch_preamble(params: &PreambleParams<'_>) -> String {
    let PreambleParams {
        task_id,
        dispatch_id,
        coordinator_handle,
        ..
    } = params;
    let post_done = build_post_worker_done_instructions(params.worker_kind);
    let header = format!(
        r#"You are working inside Alera, a multi-agent IDE. You are a dispatched worker.
Your coordinator's terminal handle is: {coordinator_handle}
Your task ID is: {task_id}
Your dispatch ID is: {dispatch_id}

You talk to the coordinator only through the CLI commands below. Do not use
Slack, GitHub comments, or any other channel to reach a human during the run.

=== CLI COMMANDS ===

  # Accept before beginning. Execution timers start only after this succeeds.
  alera orchestration dispatch-accept

  # Inspect the context installed for this terminal.
  alera orchestration --json context

  # Optional semantic phase update. Runtime activity also renews liveness.
  alera orchestration heartbeat --phase "<investigating|implementing|reviewing|waiting>"

  # Atomically commit a successful or failed result. Do this exactly once.
  alera orchestration complete --summary "<what was completed and remaining work>" --completion-kind success --files-modified "path/a,path/b" --artifacts '[]' --validation '[]'

  # Ask the coordinator a question and block until it answers.
  #
  # BEHAVIOR RULE #1 (MUST NOT VIOLATE):
  # NEVER use AskUserQuestion; use `alera orchestration ask` or send
  # --type decision_gate. AskUserQuestion opens a local TUI prompt that the
  # coordinator cannot see and cannot answer - your session will hang forever
  # waiting on a human. Every interactive question goes through `ask` below.
  #
  # The `ask` verb is a thin wrapper: it sends a decision_gate message and
  # blocks until the coordinator replies, then prints the reply body. Use it
  # anywhere you would otherwise have reached for AskUserQuestion.
  alera orchestration ask --to {coordinator_handle} --question "<your question>" --options "<optional,comma,separated>" --timeout-ms 600000

  # Escalate a blocker or failure (pre-completion, when you need the
  # coordinator to do something before you can continue):
  alera orchestration escalate --subject "Blocked: <reason>" --body "<details>"

  # Check for messages from the coordinator:
  alera orchestration check

{post_done}"#,
    );

    let drift = params
        .base_drift
        .filter(|drift| drift.behind > 0)
        .map(build_drift_section)
        .unwrap_or_default();
    let gate = params
        .gate_resolution
        .map(build_gate_section)
        .unwrap_or_default();

    format!(
        "{header}{drift}{gate}\n\n=== TASK ===\n{spec}",
        spec = params.task_spec
    )
}

/// Defense-in-depth: the worker sees the drift from line 1 instead of
/// discovering it via stale line numbers in artifacts later.
fn build_drift_section(drift: &BaseDrift) -> String {
    let subjects = drift
        .recent_subjects
        .iter()
        .map(|subject| format!("  - {subject}"))
        .collect::<Vec<_>>()
        .join("\n");
    format!(
        "\n\n--- BASE DRIFT ---\nYour worktree HEAD is {behind} commits behind {base}. The 5 most recent\nsubjects on {base} NOT in your worktree:\n{subjects}\n\nIf any look relevant to your task, either pull them in (`git fetch && git rebase {base}` or equivalent) or escalate to the coordinator before starting.\n---",
        behind = drift.behind,
        base = drift.base,
    )
}

fn build_gate_section(gate: &GateResolution) -> String {
    format!(
        "\n\n--- DECISION GATE RESOLVED ---\nQuestion: {question}\nResolution: {resolution}\n---",
        question = gate.question,
        resolution = gate.resolution,
    )
}

/// Re-dispatch reaches idle agents as terminal input; inbox polling after
/// completion cannot receive that new TASK block and looks hung.
fn build_post_worker_done_instructions(worker_kind: WorkerKind) -> String {
    match worker_kind {
        WorkerKind::BareShell => r#"=== AFTER COMPLETE RETURNS ===

Successful completion ends your turn for this task. Your dispatched work is complete:
stop and take no further actions - do NOT start new or unrelated work,
do NOT run a sleep/poll loop, and do NOT keep calling
`alera orchestration check`. The coordinator has already recorded your
completion and expects no further output.

Exit the shell after completion. Bare-shell workers have no idle agent
prompt for Alera to reuse; if the coordinator has more for you it will
dispatch or prompt another worker with a fresh TASK block."#
            .to_string(),
        WorkerKind::PromptReturningAgent => r#"=== AFTER COMPLETE RETURNS ===

Successful completion ends your turn for this task. Your dispatched work is complete:
stop, return to an idle prompt, and take no further actions - do NOT start
new or unrelated work, do NOT run a sleep/poll loop, and do NOT keep calling
`alera orchestration check`. The coordinator has already recorded your
completion and expects no further output.

Do not exit the shell. Your terminal stays available, and if the
coordinator has more for you it will re-engage this terminal with a fresh
preamble + TASK block, which arrives as new input. When that happens,
reset and start the new task; ignore the previous task's follow-ups."#
            .to_string(),
    }
}

/// Scans the spec for a literal `allow-stale-base: true` line (canonical
/// form only, no regex) and returns whether it was present plus the spec
/// with the directive stripped so the worker's TASK block never sees it.
pub fn parse_allow_stale_base_from_spec(spec: &str) -> (bool, String) {
    let mut allowed = false;
    let kept: Vec<&str> = spec
        .lines()
        .filter(|line| {
            if line.trim() == "allow-stale-base: true" {
                allowed = true;
                false
            } else {
                true
            }
        })
        .collect();
    (allowed, kept.join("\n"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn params<'a>(
        drift: Option<&'a BaseDrift>,
        gate: Option<&'a GateResolution>,
    ) -> PreambleParams<'a> {
        PreambleParams {
            task_id: "task_1",
            dispatch_id: "ctx_1",
            task_spec: "Fix the login button CSS",
            coordinator_handle: "term_coord",
            base_drift: drift,
            gate_resolution: gate,
            worker_kind: WorkerKind::PromptReturningAgent,
        }
    }

    #[test]
    fn preamble_contains_contract_commands() {
        let preamble = build_dispatch_preamble(&params(None, None));
        assert!(preamble.contains("Your task ID is: task_1"));
        assert!(preamble.contains("Your dispatch ID is: ctx_1"));
        assert!(preamble.contains("alera orchestration dispatch-accept"));
        assert!(preamble.contains("alera orchestration heartbeat"));
        assert!(preamble.contains("alera orchestration complete"));
        assert!(preamble.contains("NEVER use AskUserQuestion"));
        assert!(preamble.contains("alera orchestration ask --to term_coord"));
        assert!(preamble.contains("=== TASK ===\nFix the login button CSS"));
        assert!(!preamble.contains("\\\n"));
        assert!(!preamble.contains("BASE DRIFT"));
        assert!(!preamble.contains("DECISION GATE RESOLVED"));
    }

    #[test]
    fn post_worker_done_instructs_idle_without_polling() {
        let preamble = build_dispatch_preamble(&params(None, None));
        assert!(preamble.contains("return to an idle prompt"));
        assert!(preamble.contains("do NOT run a sleep/poll loop"));
        assert!(preamble.contains("do NOT keep calling"));
        assert!(!preamble.contains("every 2 minutes"));
        assert!(!preamble.contains("grace period (10 minutes)"));
        assert!(!preamble.contains("Poll with"));
    }

    #[test]
    fn bare_shell_post_worker_done_exits() {
        let mut bare = params(None, None);
        bare.worker_kind = WorkerKind::BareShell;
        let preamble = build_dispatch_preamble(&bare);
        assert!(preamble.contains("Exit the shell after completion"));
        assert!(preamble.contains("Bare-shell workers"));
        assert!(!preamble.contains("return to an idle prompt"));
    }

    #[test]
    fn drift_section_appended_only_when_behind() {
        let drift = BaseDrift {
            base: "origin/main".to_string(),
            behind: 25,
            recent_subjects: vec!["fix: a".to_string(), "feat: b".to_string()],
        };
        let preamble = build_dispatch_preamble(&params(Some(&drift), None));
        assert!(preamble.contains("--- BASE DRIFT ---"));
        assert!(preamble.contains("25 commits behind origin/main"));
        assert!(preamble.contains("  - fix: a"));
        assert!(preamble.contains("git fetch && git rebase origin/main"));
        assert!(!preamble.contains("git pull --rebase\norigin/main"));

        let zero = BaseDrift {
            base: "origin/main".to_string(),
            behind: 0,
            recent_subjects: vec![],
        };
        let clean = build_dispatch_preamble(&params(Some(&zero), None));
        assert!(!clean.contains("BASE DRIFT"));
    }

    #[test]
    fn gate_resolution_appended() {
        let gate = GateResolution {
            question: "Proceed with migration?".to_string(),
            resolution: "Yes, but keep backups".to_string(),
        };
        let preamble = build_dispatch_preamble(&params(None, Some(&gate)));
        assert!(preamble.contains("--- DECISION GATE RESOLVED ---"));
        assert!(preamble.contains("Question: Proceed with migration?"));
        assert!(preamble.contains("Resolution: Yes, but keep backups"));
    }

    #[test]
    fn allow_stale_base_is_parsed_and_stripped() {
        let spec = "Do the thing\nallow-stale-base: true\nCarefully.";
        let (allowed, stripped) = parse_allow_stale_base_from_spec(spec);
        assert!(allowed);
        assert_eq!(stripped, "Do the thing\nCarefully.");

        let (not_allowed, unchanged) = parse_allow_stale_base_from_spec("Do the thing");
        assert!(!not_allowed);
        assert_eq!(unchanged, "Do the thing");

        // Non-canonical forms are not honored.
        let (loose, _) = parse_allow_stale_base_from_spec("allow-stale-base:true");
        assert!(!loose);
    }
}
