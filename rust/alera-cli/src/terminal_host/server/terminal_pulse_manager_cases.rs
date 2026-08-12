use super::*;

fn insert_rule(manager: &mut TerminalPulseManager, session_id: &str, watermark: u64) {
    manager.rules.insert(
        session_id.to_string(),
        TerminalPulseRule {
            workspace_id: "workspace-1".to_string(),
            session_instance_id: 7,
            configuration: TerminalPulseConfiguration::default(),
            generation: 0,
            pending: false,
            activated_after_event_sequence: watermark,
            active: Arc::new(AtomicBool::new(true)),
        },
    );
}

#[test]
fn fixed_window_ignores_changes_until_the_due_pulse_is_taken() {
    let mut manager = TerminalPulseManager::default();
    insert_rule(&mut manager, "session-1", 0);

    let first = manager.schedule("workspace-1", 1);
    assert_eq!(first.len(), 1);
    assert!(manager.schedule("workspace-1", 2).is_empty());
    assert_eq!(manager.due_bytes("session-1", 7, 1), Some(b"r\r".to_vec()));
    manager.complete_due("session-1", 7, 1);
    assert!(manager.schedule("workspace-1", 2).is_empty());
    assert_eq!(manager.schedule("workspace-1", 3).len(), 1);
}

#[test]
fn fixed_window_ignores_observed_changes_not_yet_delivered_by_the_watcher() {
    let mut manager = TerminalPulseManager::default();
    insert_rule(&mut manager, "session-1", 0);

    assert_eq!(manager.schedule("workspace-1", 1).len(), 1);
    manager.complete_due_at_sequence("session-1", 7, 1, 2);

    assert!(manager.schedule("workspace-1", 2).is_empty());
    assert_eq!(manager.schedule("workspace-1", 3).len(), 1);
}

#[test]
fn rules_ignore_events_at_or_before_their_arm_watermark() {
    let mut manager = TerminalPulseManager::default();
    for (session_id, watermark) in [("session-1", 5), ("session-2", 7)] {
        insert_rule(&mut manager, session_id, watermark);
    }

    assert!(manager.schedule("workspace-1", 5).is_empty());
    assert_eq!(
        manager.schedule("workspace-1", 6)[0].session_id,
        "session-1",
    );
    assert!(manager.schedule("workspace-1", 7).is_empty());
    manager.complete_due("session-1", 7, 1);
    let schedules = manager.schedule("workspace-1", 8);
    assert_eq!(schedules.len(), 2);
}
