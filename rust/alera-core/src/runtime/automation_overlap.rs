use super::{AutomationOverlapPolicy, AutomationRun, AutomationRunStatus};

/// What a run about to start does about the other active runs of its
/// automation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AutomationOverlapDecision {
    Proceed,
    /// Stay pending; a later tick tries again.
    Wait,
    Skip(&'static str),
    QueueLimit,
}

pub const AUTOMATION_OVERLAP_SKIP_REASON: &str = "an automation run is already active";
pub const AUTOMATION_OVERLAP_SUPERSEDED_REASON: &str =
    "a newer occurrence replaced this queued run";
pub const AUTOMATION_QUEUE_LIMIT_REASON: &str = "automation queue cap reached";
const AUTOMATION_TARGET_BUSY_REASON: &str = "the automation target is busy";

/// Decides how `this_run_id` treats the other active runs of the same
/// automation. `active` may include the run itself. The returned ids are
/// older pending runs the caller marks superseded before acting on the
/// decision.
///
/// Run numbers order the runs: they only grow within an automation, so a
/// queued run resumed on a later tick still knows which runs came before it.
pub fn decide_overlap(
    policy: AutomationOverlapPolicy,
    queue_cap: i64,
    this_run_id: &str,
    active: &[AutomationRun],
) -> (AutomationOverlapDecision, Vec<String>) {
    let this_number = active
        .iter()
        .find(|run| run.id == this_run_id)
        .map_or(i64::MAX, |run| run.number);
    let others = active.iter().filter(|run| run.id != this_run_id);
    let pending = |run: &&AutomationRun| run.status == AutomationRunStatus::Pending;
    let older_pending: Vec<&AutomationRun> = others
        .clone()
        .filter(pending)
        .filter(|run| run.number < this_number)
        .collect();
    let newer_pending = others
        .clone()
        .filter(pending)
        .any(|run| run.number > this_number);
    let running = others.clone().any(|run| !pending(&run));
    match policy {
        AutomationOverlapPolicy::ForceParallel => (AutomationOverlapDecision::Proceed, Vec::new()),
        AutomationOverlapPolicy::Skip => {
            if others.clone().next().is_some() {
                (
                    AutomationOverlapDecision::Skip(AUTOMATION_OVERLAP_SKIP_REASON),
                    Vec::new(),
                )
            } else {
                (AutomationOverlapDecision::Proceed, Vec::new())
            }
        }
        AutomationOverlapPolicy::RunLatestOnce => {
            if newer_pending {
                return (
                    AutomationOverlapDecision::Skip(AUTOMATION_OVERLAP_SUPERSEDED_REASON),
                    Vec::new(),
                );
            }
            let superseded = older_pending.iter().map(|run| run.id.clone()).collect();
            let decision = if running {
                AutomationOverlapDecision::Wait
            } else {
                AutomationOverlapDecision::Proceed
            };
            (decision, superseded)
        }
        AutomationOverlapPolicy::Queue => {
            let decision = if older_pending.len() >= queue_cap.clamp(1, 10) as usize {
                AutomationOverlapDecision::QueueLimit
            } else if running || !older_pending.is_empty() {
                AutomationOverlapDecision::Wait
            } else {
                AutomationOverlapDecision::Proceed
            };
            (decision, Vec::new())
        }
    }
}

/// What a run does when its target is held by something other than another
/// run of the same automation.
pub fn busy_target_decision(policy: AutomationOverlapPolicy) -> AutomationOverlapDecision {
    match policy {
        AutomationOverlapPolicy::Skip => {
            AutomationOverlapDecision::Skip(AUTOMATION_TARGET_BUSY_REASON)
        }
        AutomationOverlapPolicy::Queue | AutomationOverlapPolicy::RunLatestOnce => {
            AutomationOverlapDecision::Wait
        }
        AutomationOverlapPolicy::ForceParallel => AutomationOverlapDecision::Proceed,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use AutomationOverlapDecision::{Proceed, QueueLimit, Skip, Wait};
    use AutomationOverlapPolicy::{ForceParallel, Queue, RunLatestOnce};

    fn run(id: &str, number: i64, status: AutomationRunStatus) -> AutomationRun {
        serde_json::from_value(serde_json::json!({
            "id": id,
            "automationId": "automation",
            "number": number,
            "occurrenceKey": format!("occurrence-{number}"),
            "scheduledAt": "2026-01-01T00:00:00Z",
            "trigger": "scheduled",
            "status": status.as_str(),
            "attemptCount": 0,
            "createdAt": "2026-01-01T00:00:00Z",
            "updatedAt": "2026-01-01T00:00:00Z",
        }))
        .unwrap()
    }

    fn pending(id: &str, number: i64) -> AutomationRun {
        run(id, number, AutomationRunStatus::Pending)
    }

    fn running(id: &str, number: i64) -> AutomationRun {
        run(id, number, AutomationRunStatus::Dispatched)
    }

    #[test]
    fn a_run_with_no_other_active_run_always_proceeds() {
        for policy in [
            AutomationOverlapPolicy::Skip,
            Queue,
            RunLatestOnce,
            ForceParallel,
        ] {
            let alone = [pending("this", 1)];
            assert_eq!(decide_overlap(policy, 1, "this", &alone), (Proceed, vec![]));
            assert_eq!(decide_overlap(policy, 1, "this", &[]), (Proceed, vec![]));
        }
    }

    #[test]
    fn skip_skips_while_any_other_run_is_pending_or_running() {
        for other in [pending("other", 1), running("other", 1)] {
            let active = [other, pending("this", 2)];
            assert_eq!(
                decide_overlap(AutomationOverlapPolicy::Skip, 10, "this", &active),
                (Skip(AUTOMATION_OVERLAP_SKIP_REASON), vec![])
            );
        }
    }

    #[test]
    fn run_latest_once_supersedes_older_pending_runs() {
        let active = [pending("a", 1), pending("b", 2), pending("this", 3)];
        assert_eq!(
            decide_overlap(RunLatestOnce, 10, "this", &active),
            (Proceed, vec!["a".to_string(), "b".to_string()])
        );
        let active = [running("a", 1), pending("b", 2), pending("this", 3)];
        assert_eq!(
            decide_overlap(RunLatestOnce, 10, "this", &active),
            (Wait, vec!["b".to_string()])
        );
        let active = [pending("this", 1), pending("newer", 2)];
        assert_eq!(
            decide_overlap(RunLatestOnce, 10, "this", &active),
            (Skip(AUTOMATION_OVERLAP_SUPERSEDED_REASON), vec![])
        );
    }

    #[test]
    fn queue_waits_in_order_and_refuses_past_its_cap() {
        let active = [running("a", 1), pending("this", 2)];
        assert_eq!(decide_overlap(Queue, 2, "this", &active), (Wait, vec![]));
        let active = [running("a", 1), pending("b", 2), pending("this", 3)];
        assert_eq!(decide_overlap(Queue, 2, "this", &active), (Wait, vec![]));
        assert_eq!(
            decide_overlap(Queue, 1, "this", &active),
            (QueueLimit, vec![])
        );
        let active = [pending("b", 2), pending("this", 3)];
        assert_eq!(decide_overlap(Queue, 5, "this", &active), (Wait, vec![]));
        let active = [pending("this", 2), pending("c", 3)];
        assert_eq!(decide_overlap(Queue, 1, "this", &active), (Proceed, vec![]));
        let crowded: Vec<_> = (1..=10)
            .map(|number| pending(&format!("p{number}"), number))
            .chain([pending("this", 11)])
            .collect();
        assert_eq!(
            decide_overlap(Queue, 50, "this", &crowded),
            (QueueLimit, vec![])
        );
        assert_eq!(
            decide_overlap(Queue, 0, "this", &[running("a", 1), pending("this", 2)]).0,
            Wait
        );
    }

    #[test]
    fn a_run_missing_from_the_active_list_counts_as_the_newest() {
        let active = [pending("a", 1)];
        assert_eq!(
            decide_overlap(RunLatestOnce, 10, "this", &active),
            (Proceed, vec!["a".to_string()])
        );
        assert_eq!(
            decide_overlap(Queue, 1, "this", &active),
            (QueueLimit, vec![])
        );
    }

    #[test]
    fn force_parallel_ignores_every_other_run() {
        let active = [running("a", 1), pending("b", 2), pending("this", 3)];
        assert_eq!(
            decide_overlap(ForceParallel, 1, "this", &active),
            (Proceed, vec![])
        );
    }

    #[test]
    fn a_busy_target_follows_the_overlap_policy() {
        assert_eq!(
            busy_target_decision(AutomationOverlapPolicy::Skip),
            Skip(AUTOMATION_TARGET_BUSY_REASON)
        );
        assert_eq!(busy_target_decision(Queue), Wait);
        assert_eq!(busy_target_decision(RunLatestOnce), Wait);
        assert_eq!(busy_target_decision(ForceParallel), Proceed);
    }
}
