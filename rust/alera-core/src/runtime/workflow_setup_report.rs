use super::{WorktreeSetupReport, WorktreeSetupStepKind, WorktreeSetupStepReport};

const DETAIL_BUDGET: usize = 240 * 1024;

pub(super) fn bounded_report(report: &WorktreeSetupReport) -> anyhow::Result<String> {
    let mut steps = Vec::new();
    let mut bytes = 0;
    let mut omitted = 0;
    let mut failed = 0;
    let mut truncated = false;
    for step in &report.steps {
        let mut step = step.clone();
        truncated |= truncate(&mut step.label);
        for value in [
            &mut step.message,
            &mut step.stdout_tail,
            &mut step.stderr_tail,
        ]
        .into_iter()
        .flatten()
        {
            truncated |= truncate(value);
        }
        let size = serde_json::to_vec(&step)?.len() + 1;
        if bytes + size <= DETAIL_BUDGET {
            bytes += size;
            steps.push(step);
        } else {
            omitted += 1;
            failed += usize::from(!step.succeeded);
        }
    }
    if omitted > 0 || truncated {
        steps.push(WorktreeSetupStepReport {
            kind: WorktreeSetupStepKind::Config,
            label: "Setup Report Summary".into(),
            succeeded: failed == 0,
            message: Some(format!("Report details were bounded: {omitted} steps omitted ({failed} failed); oversized text truncated: {truncated}. The setup outcome is unchanged.")),
            exit_code: None,
            stdout_tail: None,
            stderr_tail: None,
        });
    }
    Ok(serde_json::to_string(&WorktreeSetupReport { steps })?)
}

fn truncate(value: &mut String) -> bool {
    if value.len() <= 4096 {
        return false;
    }
    let end = value.floor_char_boundary(4096);
    value.truncate(end);
    value.push_str(" [truncated]");
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn workflow_setup_reports_preserve_success_and_omitted_failures_with_bounded_json() {
        let step = WorktreeSetupStepReport {
            kind: WorktreeSetupStepKind::Copy,
            label: "copied file".repeat(30),
            succeeded: true,
            message: Some("\u{1f680}\n\"".repeat(4000)),
            exit_code: None,
            stdout_tail: None,
            stderr_tail: None,
        };
        let mut report = WorktreeSetupReport {
            steps: vec![step; 2000],
        };
        for succeeds in [true, false] {
            report.steps.last_mut().unwrap().succeeded = succeeds;
            let json = bounded_report(&report).unwrap();
            assert!(json.len() < 262_144);
            let bounded: WorktreeSetupReport = serde_json::from_str(&json).unwrap();
            assert_eq!(bounded.steps.iter().all(|step| step.succeeded), succeeds);
            assert!(bounded
                .steps
                .last()
                .unwrap()
                .message
                .as_ref()
                .unwrap()
                .contains("steps omitted"));
        }
    }
}
