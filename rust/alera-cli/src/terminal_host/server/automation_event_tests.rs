use super::*;
use crate::terminal_host::client::ClientFrame;
use alera_core::runtime::{AutomationOccurrence, AutomationRunStatus, AutomationRunTrigger};
use serde_json::Value;

fn drain_events(fixture: &mut Harness) -> Vec<Value> {
    let mut events = Vec::new();
    while let Ok(frame) = fixture.events.try_recv() {
        let value = match frame {
            ClientFrame::Json(value) => value,
            ClientFrame::OrderedControl { frame, .. } => match *frame {
                ClientFrame::Json(value) => value,
                _ => continue,
            },
            _ => continue,
        };
        if value["event"]
            .as_str()
            .is_some_and(|name| name.starts_with("automation"))
        {
            events.push(value);
        }
    }
    events
}

fn named<'a>(events: &'a [Value], name: &str) -> Vec<&'a Value> {
    events
        .iter()
        .filter(|event| event["event"] == name)
        .collect()
}

#[tokio::test]
async fn every_definition_mutation_broadcasts_its_automation_once() {
    let mut fixture = harness().await;
    let input = json!({"name":"Review","promptTemplate":"Review","schedule":{"recurring":{"cron":"0 9 * * *","timezone":"UTC"}},"target":{"freshTab":{"workspaceId":"workspace-1","agentProfileId":"profile-1"}}});
    let created = fixture
        .actor
        .handle_automation_request(1, "automation.create", &json!({ "automation": input }))
        .await
        .unwrap();
    let id = created["id"].as_str().unwrap().to_string();
    let steps = [
        ("automation.create", None),
        (
            "automation.patch",
            Some(json!({"id": id, "changes": {"name": "Renamed"}})),
        ),
        (
            "automation.pause",
            Some(json!({"id": id, "activeRuns": "continue-active"})),
        ),
        ("automation.resume", Some(json!({"id": id}))),
        ("automation.trash", Some(json!({"id": id}))),
        ("automation.restore", Some(json!({"id": id}))),
    ];
    for (verb, payload) in steps {
        if let Some(payload) = payload {
            fixture
                .actor
                .handle_automation_request(1, verb, &payload)
                .await
                .unwrap_or_else(|error| panic!("{verb}: {error}"));
        }
        let events = drain_events(&mut fixture);
        let changed = named(&events, "automationsChanged");
        assert_eq!(changed.len(), 1, "{verb}: {events:?}");
        assert_eq!(changed[0]["payload"]["automationId"], id.as_str(), "{verb}");
    }
}

#[tokio::test]
async fn manual_overlap_decisions_broadcast_each_run_status() {
    let mut fixture = harness().await;
    let mut definition = upsert_draft(&mut fixture.actor).await;
    definition.overlap_policy = AutomationOverlapPolicy::Queue;
    let busy = fixture
        .actor
        .runtime_store
        .create_automation_run(
            &definition,
            &AutomationOccurrence {
                automation_id: definition.id.clone(),
                key: "manual|busy".into(),
                scheduled_at: Utc::now(),
                local_time: "test".into(),
            },
            AutomationRunTrigger::Manual,
        )
        .await
        .unwrap();
    fixture
        .actor
        .runtime_store
        .begin_automation_attempt(&busy.id, 3)
        .await
        .unwrap();
    drain_events(&mut fixture);

    let queued = fixture
        .actor
        .handle_automation_request(
            1,
            "automation.runNow",
            &json!({"id": definition.id, "overlap": "queue"}),
        )
        .await
        .unwrap();
    assert_eq!(queued["status"], "pending");
    let events = drain_events(&mut fixture);
    let runs = named(&events, "automationRunChanged");
    assert_eq!(runs[0]["payload"]["runId"], queued["id"]);
    assert_eq!(runs[0]["payload"]["status"], "pending");
    let audit = fixture
        .actor
        .runtime_store
        .list_automation_audit_events(Some(&definition.id), 20)
        .await
        .unwrap();
    assert!(audit
        .iter()
        .any(|event| event.action == "runNowQueued"
            && event.run_id.as_deref() == queued["id"].as_str()));
    assert!(!audit.iter().any(|event| event.action == "runNow"));

    let skipped = fixture
        .actor
        .handle_automation_request(
            1,
            "automation.runNow",
            &json!({"id": definition.id, "overlap": "skip"}),
        )
        .await
        .unwrap();
    assert_eq!(skipped["status"], "overlapSkipped");
    let events = drain_events(&mut fixture);
    let statuses: Vec<_> = named(&events, "automationRunChanged")
        .into_iter()
        .filter(|event| event["payload"]["runId"] == skipped["id"])
        .map(|event| event["payload"]["status"].clone())
        .collect();
    assert_eq!(statuses, vec![json!("pending"), json!("overlapSkipped")]);
}

#[tokio::test]
async fn missed_occurrences_are_claimed_without_runs_and_audited_once() {
    let mut fixture = harness().await;
    let mut definition = draft_definition();
    definition.state = AutomationState::Active;
    definition.misfire_grace_seconds = 0;
    definition.misfire_policy = AutomationMisfirePolicy::Skip;
    // The schedule ends in the past: an open-ended one would make the current
    // minute due, and a tick within a second of the boundary runs it on time.
    let now = Utc::now();
    let start = now - chrono::Duration::minutes(501);
    let end = now - chrono::Duration::minutes(1);
    definition.schedule = AutomationSchedule::Recurring {
        cron: "* * * * *".into(),
        timezone: "UTC".into(),
        start_at: Some(start),
        end_at: Some(end),
        max_scheduled_runs: None,
    };
    let definition = fixture
        .actor
        .runtime_store
        .upsert_automation(definition.clone(), definition.created_by.clone())
        .await
        .unwrap();
    let audit_batches = |audit: &[alera_core::runtime::AutomationAuditEvent]| {
        audit
            .iter()
            .filter(|event| event.action == "misfiresSkipped")
            .map(|event| event.details.clone())
            .collect::<Vec<_>>()
    };
    // The catch-up budget may split a slow tick; each tick still writes one
    // audit entry for everything it skipped.
    let mut ticks = 0;
    let latest = loop {
        fixture.actor.handle_automation_tick().await;
        ticks += 1;
        let audit = fixture
            .actor
            .runtime_store
            .list_automation_audit_events(Some(&definition.id), 100)
            .await
            .unwrap();
        assert_eq!(
            audit_batches(&audit).len(),
            ticks,
            "one audit entry per tick"
        );
        let latest = fixture
            .actor
            .runtime_store
            .latest_automation_occurrence(&definition.id)
            .await
            .unwrap()
            .unwrap();
        if latest > end - chrono::Duration::minutes(1) || ticks == 20 {
            break latest;
        }
    };
    let runs = fixture
        .actor
        .runtime_store
        .list_automation_runs(Some(&definition.id), 1000)
        .await
        .unwrap();
    assert!(runs.is_empty(), "missed occurrences must not create runs");
    let audit = fixture
        .actor
        .runtime_store
        .list_automation_audit_events(Some(&definition.id), 100)
        .await
        .unwrap();
    let batches = audit_batches(&audit);
    let count: u64 = batches
        .iter()
        .map(|details| details["count"].as_u64().unwrap())
        .sum();
    assert!(count >= 499, "missed {count} of 500 occurrences");
    assert_eq!(batches[0]["to"], serde_json::to_value(latest).unwrap());
    assert!(
        latest > start,
        "the cursor moved past the missed occurrences"
    );
    let events = drain_events(&mut fixture);
    assert!(named(&events, "automationRunChanged").is_empty());
}

#[tokio::test]
async fn run_status_helper_reports_the_new_status() {
    let mut fixture = harness().await;
    let definition = upsert_draft(&mut fixture.actor).await;
    let run = fixture
        .actor
        .runtime_store
        .create_automation_run(
            &definition,
            &AutomationOccurrence {
                automation_id: definition.id.clone(),
                key: "manual|cancel".into(),
                scheduled_at: Utc::now(),
                local_time: "test".into(),
            },
            AutomationRunTrigger::Manual,
        )
        .await
        .unwrap();
    drain_events(&mut fixture);
    fixture
        .actor
        .set_automation_run_status(&run.id, AutomationRunStatus::Cancelled, None)
        .await
        .unwrap();
    let events = drain_events(&mut fixture);
    let runs = named(&events, "automationRunChanged");
    assert_eq!(runs.len(), 1);
    assert_eq!(
        runs[0]["payload"],
        json!({"automationId": definition.id, "runId": run.id, "status": "cancelled"})
    );
}
