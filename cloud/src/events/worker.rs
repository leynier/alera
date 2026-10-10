//! The delivery loop and the internal pump the edge cron can call when Cloud Run
//! throttles CPU between requests.

use std::time::Duration;

use axum::{extract::State, Json};
use tokio::time::Instant;

use crate::{error::ApiError, state::AppState};

use super::delivery::{run_pass, PassSummary};

const IDLE_POLL: Duration = Duration::from_secs(2);
const PUMP_BUDGET: Duration = Duration::from_secs(20);

/// Runs passes until one finds nothing to do, bounded by `budget`.
pub async fn drain(state: &AppState, budget: Duration) -> Result<PassSummary, ApiError> {
    let deadline = Instant::now() + budget;
    let mut total = PassSummary::default();
    loop {
        let pass = run_pass(state).await?;
        total.fanned_out += pass.fanned_out;
        total.claimed += pass.claimed;
        total.delivered += pass.delivered;
        if pass.claimed == 0 && pass.fanned_out == 0 || Instant::now() >= deadline {
            return Ok(total);
        }
    }
}

pub fn spawn(state: AppState) -> tokio::task::JoinHandle<()> {
    tokio::spawn(async move {
        loop {
            if let Err(error) = drain(&state, Duration::from_secs(60)).await {
                tracing::warn!(error = %error, "event delivery pass failed");
            }
            tokio::select! {
                _ = state.events.wake.notified() => {}
                _ = tokio::time::sleep(IDLE_POLL) => {}
            }
        }
    })
}

/// `POST /v1/internal/event-deliveries/pump`: one bounded drain. The edge never
/// forwards this path from the internet; its cron calls the origin directly.
pub async fn pump(State(state): State<AppState>) -> Result<Json<PassSummary>, ApiError> {
    Ok(Json(drain(&state, PUMP_BUDGET).await?))
}
