use std::sync::Arc;
use std::time::Duration;

use alera_core::runtime::{next_occurrence, AutomationSchedule, AutomationState, RuntimeStore};
use chrono::{DateTime, Utc};
use tokio::sync::{mpsc::UnboundedSender, Notify};
use tokio::task::JoinHandle;

use super::ServerCommand;

const NO_ACTIVE_AUTOMATION_SLEEP: Duration = Duration::from_secs(60);
const MAX_AUTOMATION_SLEEP: Duration = Duration::from_secs(15 * 60);

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
    for definition in definitions {
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
    let Some(nearest) = nearest else {
        return Ok(NO_ACTIVE_AUTOMATION_SLEEP);
    };
    if nearest <= now {
        return Ok(Duration::ZERO);
    }
    let delay = (nearest - now)
        .to_std()
        .map_err(|_| "automation schedule produced a negative delay".to_string())?;
    Ok(delay.min(MAX_AUTOMATION_SLEEP))
}

#[cfg(test)]
mod tests {
    use super::MAX_AUTOMATION_SLEEP;

    #[test]
    fn scheduler_sleep_has_a_bounded_wakeup() {
        assert_eq!(MAX_AUTOMATION_SLEEP, std::time::Duration::from_secs(900));
    }
}
