//! Check rollup counts for a pull request summary row, mirroring
//! `deriveReviewChecksRollup` plus the counts the desktop sidebar keeps:
//! failure dominates, non-terminal runs count as pending, and at most three
//! failing names ride along for the row tooltip. The GraphQL batch and the
//! per-workspace snapshot describe checks in different shapes, so each caller
//! classifies its own and the counting lives here once.

use serde_json::Value;

/// One check reduced to what the rollup needs: `(name, failed, pending)`.
pub(super) type ClassifiedCheck = (String, bool, bool);

pub(super) fn status_rollup_contexts(snapshot: &Value) -> Vec<Value> {
    snapshot
        .get("commits")
        .and_then(|commits| commits.get("nodes"))
        .and_then(Value::as_array)
        .and_then(|nodes| nodes.first())
        .and_then(|node| node.get("commit"))
        .and_then(|commit| commit.get("statusCheckRollup"))
        .and_then(|rollup| rollup.get("contexts"))
        .and_then(|contexts| contexts.get("nodes"))
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
}

/// Rolled-up status across the checks of one review.
#[derive(Debug)]
pub(super) struct CheckCounts {
    pub(super) rollup: &'static str,
    pub(super) pending: i64,
    pub(super) failed: i64,
    pub(super) failing_names: Vec<String>,
}

/// Counts the `StatusCheckRollupContext` entries of a GraphQL review.
pub(super) fn count_check_contexts(contexts: &[Value]) -> CheckCounts {
    count_classified_checks(contexts.iter().filter_map(classify_check))
}

pub(super) fn count_classified_checks(
    checks: impl IntoIterator<Item = ClassifiedCheck>,
) -> CheckCounts {
    let mut pending = 0_i64;
    let mut failed = 0_i64;
    let mut failing_names = Vec::<String>::new();
    let mut any_pending = false;
    let mut any = false;
    for (name, failed_check, pending_check) in checks {
        any = true;
        if failed_check {
            failed += 1;
            if failing_names.len() < 3 {
                failing_names.push(name);
            }
            continue;
        }
        if pending_check {
            any_pending = true;
            pending += 1;
        }
    }
    let rollup = if !any {
        "none"
    } else if failed > 0 {
        "failure"
    } else if any_pending {
        "pending"
    } else {
        "success"
    };
    CheckCounts {
        rollup,
        pending,
        failed,
        failing_names,
    }
}

/// Maps one GraphQL `StatusCheckRollupContext` union entry to
/// `(name, failed, counts-as-pending)`, the neutral projection of
/// `mapGitHubStatusRollupCheck`. Modern Actions runs arrive as `CheckRun` and
/// legacy commit statuses as `StatusContext`.
fn classify_check(context: &Value) -> Option<ClassifiedCheck> {
    let name = || {
        context
            .get("name")
            .and_then(Value::as_str)
            .or_else(|| context.get("context").and_then(Value::as_str))
            .unwrap_or("check")
            .to_string()
    };
    if context.get("__typename").and_then(Value::as_str) == Some("StatusContext") {
        let state = context
            .get("state")
            .and_then(Value::as_str)
            .unwrap_or("PENDING")
            .to_ascii_uppercase();
        let pending = state == "EXPECTED" || state == "PENDING";
        let failed = state == "ERROR" || state == "FAILURE";
        return Some((name(), failed, pending));
    }
    let status = context
        .get("status")
        .and_then(Value::as_str)
        .unwrap_or("QUEUED")
        .to_ascii_uppercase();
    let completed = status == "COMPLETED";
    let conclusion = context
        .get("conclusion")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_ascii_uppercase();
    let failed = matches!(
        conclusion.as_str(),
        "FAILURE" | "STARTUP_FAILURE" | "CANCELLED" | "STALE" | "TIMED_OUT" | "ACTION_REQUIRED"
    );
    let pending = !completed || conclusion == "PENDING";
    Some((name(), failed, pending))
}
