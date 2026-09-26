use anyhow::Result;
use std::sync::atomic::Ordering;

use super::RuntimeStore;

impl RuntimeStore {
    /// Called after actor-owned mutations settle, never for terminal output or
    /// from a new timer. Repeated lifecycle checks without writes emit no event.
    pub async fn take_orchestration_board_change(&self) -> Result<Option<i64>> {
        let revision = self.orchestration_board_revision().await?;
        let previous = self
            .board_notification_revision
            .fetch_max(revision, Ordering::Relaxed);
        Ok((revision > previous).then_some(revision))
    }
}
