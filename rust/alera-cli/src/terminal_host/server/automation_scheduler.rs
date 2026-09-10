use std::sync::Arc;
use std::time::Duration;

use alera_core::runtime::{next_occurrence, AutomationSchedule, AutomationState, RuntimeStore};
use chrono::{DateTime, Utc};
use tokio::sync::{mpsc::UnboundedSender, Notify};
use tokio::task::JoinHandle;

use super::ServerCommand;

const NO_ACTIVE_AUTOMATION_SLEEP: Duration = Duration::from_secs(60);
const MAX_AUTOMATION_SLEEP: Duration = Duration::from_secs(15 * 60);
const OVERDUE_CIRCUIT_RETRY: Duration = Duration::from_secs(5);

pub(super) fn spawn(
    store: RuntimeStore,
    inbox: UnboundedSender<ServerCommand>,
    wake: Arc<Notify>,
) -> JoinHandle<()> {
    tokio::spawn(async move {
        loop {
            let wait = next_wait(&store)
                .await
                .unwrap_or(NO_ACTIVE_AUTOMATION_SLEEP);
            tokio::select! {
                _ = tokio::time::sleep(wait) => {
                    let _ = inbox.send(ServerCommand::AutomationTick);
                }
                _ = wake.notified() => {}
            }
        }
    })
}

async fn next_wait(store: &RuntimeStore) -> Result<Duration, String> {
    let definitions = store
        .list_automations(false)
        .await
        .map_err(|error| error.to_string())?;
    let now = Utc::now();
    let mut nearest: Option<DateTime<Utc>> = None;
    let mut overdue_circuit = false;
    for definition in definitions {
        if let Some(deadline) = definition.circuit_reset_at() {
            if deadline <= now {
                overdue_circuit = true;
            } else {
                nearest = Some(nearest.map_or(deadline, |current| current.min(deadline)));
            }
        }
        if definition.state != AutomationState::Active {
            continue;
        }
        let cursor = match &definition.schedule {
            AutomationSchedule::OneTime { .. } => DateTime::<Utc>::UNIX_EPOCH,
            AutomationSchedule::Recurring { start_at, .. } => store
                .latest_automation_occurrence(&definition.id)
                .await
                .map_err(|error| error.to_string())?
                .or(*start_at)
                .unwrap_or(definition.created_at),
        };
        if let Some(occurrence) = next_occurrence(&definition.id, &definition.schedule, cursor)
            .map_err(|error| error.to_string())?
        {
            nearest = Some(nearest.map_or(occurrence.scheduled_at, |current| {
                current.min(occurrence.scheduled_at)
            }));
        }
    }
    if nearest.is_some_and(|deadline| deadline <= now) {
        return Ok(Duration::ZERO);
    }
    if overdue_circuit {
        let retry = OVERDUE_CIRCUIT_RETRY;
        let Some(nearest) = nearest else {
            return Ok(retry);
        };
        let delay = (nearest - now)
            .to_std()
            .map_err(|_| "automation schedule produced a negative delay".to_string())?;
        return Ok(delay.min(retry).min(MAX_AUTOMATION_SLEEP));
    }
    let Some(nearest) = nearest else {
        return Ok(NO_ACTIVE_AUTOMATION_SLEEP);
    };
    let delay = (nearest - now)
        .to_std()
        .map_err(|_| "automation schedule produced a negative delay".to_string())?;
    Ok(delay.min(MAX_AUTOMATION_SLEEP))
}

#[cfg(test)]
mod tests {
    use super::{next_wait, MAX_AUTOMATION_SLEEP};
    use alera_core::runtime::{
        AutomationActor, AutomationActorKind, AutomationDefinition, AutomationMisfirePolicy,
        AutomationOverlapPolicy, AutomationSchedule, AutomationSetupPolicy, AutomationState,
        AutomationTarget, RuntimeStore,
    };
    use chrono::{Duration as ChronoDuration, Utc};
    use std::time::Duration;

    #[test]
    fn scheduler_sleep_has_a_bounded_wakeup() {
        assert_eq!(MAX_AUTOMATION_SLEEP, std::time::Duration::from_secs(900));
    }

    fn actor() -> AutomationActor {
        AutomationActor {
            kind: AutomationActorKind::LocalCli,
            id: None,
            label: None,
        }
    }

    fn definition() -> AutomationDefinition {
        let now = Utc::now();
        AutomationDefinition {
            id: "automation-circuit".into(),
            slug: "circuit".into(),
            name: "Circuit".into(),
            description: String::new(),
            project_id: None,
            tag_ids: Vec::new(),
            prompt_template: "Run".into(),
            schedule: AutomationSchedule::OneTime {
                at: now + ChronoDuration::hours(2),
                timezone: "UTC".into(),
            },
            target: AutomationTarget::FreshTab {
                workspace_id: "workspace".into(),
                agent_profile_id: "profile".into(),
            },
            setup_policy: AutomationSetupPolicy::Wait,
            cleanup_policy: None,
            overlap_policy: AutomationOverlapPolicy::Skip,
            queue_cap: 10,
            inactivity_timeout_seconds: 7200,
            heartbeat_interval_seconds: 60,
            misfire_grace_seconds: 900,
            misfire_policy: AutomationMisfirePolicy::Skip,
            retry_max_attempts: 3,
            retry_backoff_seconds: 60,
            circuit_failure_threshold: 3,
            circuit_open_seconds: 30,
            precheck: None,
            notify_on_success: false,
            circuit_opened: false,
            circuit_opened_at: None,
            state: AutomationState::Draft,
            revision: 0,
            approved_revision: None,
            created_by: actor(),
            modified_by: actor(),
            created_at: now,
            updated_at: now,
        }
    }

    #[tokio::test]
    async fn next_wait_uses_circuit_reset_deadline() {
        let directory = tempfile::tempdir().unwrap();
        let store = RuntimeStore::open(directory.path()).await.unwrap();
        sqlx::query(
            "INSERT INTO agentProfiles (id, name, agentType, command, createdAt, updatedAt) \
             VALUES ('profile', 'Profile', 'codex', 'codex', datetime('now'), datetime('now'))",
        )
        .execute(store.pool())
        .await
        .unwrap();
        let saved = store
            .upsert_automation(definition(), actor())
            .await
            .unwrap();
        store
            .set_automation_circuit_opened(&saved.id, true, actor(), Some("opened"))
            .await
            .unwrap();
        store
            .set_automation_state(&saved.id, AutomationState::Blocked, actor(), Some("opened"))
            .await
            .unwrap();

        let wait = next_wait(&store).await.unwrap();
        assert!(wait > Duration::from_secs(0));
        assert!(wait <= Duration::from_secs(30));
    }
}
