use std::{collections::BTreeMap, future::Future, time::Duration};

use sqlx::FromRow;
use tokio::{
    task::JoinSet,
    time::{timeout_at, Instant},
};
use uuid::Uuid;

use crate::{
    error::ApiError,
    fcm::{send_with_retry_until, FcmError, FcmMessage},
    push_delivery_token_cleanup::remove_unregistered_token,
    quota::reserve_push_delivery,
    state::AppState,
};

#[derive(FromRow)]
pub(crate) struct DeliveryTarget {
    pub(crate) mobile_device_id: String,
    pub(crate) token: String,
    pub(crate) attention: bool,
    pub(crate) done: bool,
    pub(crate) terminal_exit: bool,
}

#[derive(FromRow)]
struct DeliveryClaim {
    id: Uuid,
    attempt: i32,
}

enum DeliveryClaimOutcome {
    Claimed(DeliveryClaim),
    Complete,
    InProgress,
}

#[derive(Clone)]
pub(crate) struct DeliveryContext {
    pub(crate) account_id: Uuid,
    pub(crate) event_id: Uuid,
    pub(crate) title: String,
    pub(crate) body: String,
    pub(crate) data: BTreeMap<String, String>,
    pub(crate) channel_id: String,
    pub(crate) deadline: Instant,
    pub(crate) send_deadline: Instant,
}

pub(crate) const MAX_PARALLEL_DELIVERIES: usize = 4;
const DELIVERY_DB_RESERVE: Duration = Duration::from_secs(2);

pub(crate) fn delivery_send_deadline(deadline: Instant) -> Instant {
    deadline - DELIVERY_DB_RESERVE
}

pub(crate) async fn deliver_target(
    state: &AppState,
    context: DeliveryContext,
    target: DeliveryTarget,
) -> Result<bool, ApiError> {
    let claim = match claim_delivery_attempt(state, &context, &target).await? {
        DeliveryClaimOutcome::Claimed(claim) => claim,
        DeliveryClaimOutcome::Complete => return Ok(false),
        DeliveryClaimOutcome::InProgress => {
            return Err(ApiError::unavailable(
                "push_delivery_in_progress",
                "Push delivery is already in progress; retry shortly.",
            ));
        }
    };
    if Instant::now() >= context.send_deadline {
        return finalize_or_release(
            state,
            claim.id,
            claim.attempt,
            "failed",
            None,
            Some("deadline_exceeded"),
            context.deadline,
        )
        .await;
    }
    let quota = timeout_at(
        context.send_deadline,
        reserve_push_delivery(
            &state.pool,
            claim.id,
            context.account_id,
            &state.config.limits,
        ),
    )
    .await;
    let quota = match quota {
        Ok(result) => result,
        Err(_) => {
            return finalize_or_release(
                state,
                claim.id,
                claim.attempt,
                "failed",
                None,
                Some("deadline_exceeded"),
                context.deadline,
            )
            .await;
        }
    };
    match quota {
        Ok(false) => return Ok(false),
        Ok(true) => {}
        Err(error) if error.is_push_quota_rejection() => {
            let finalized = finalize_or_release(
                state,
                claim.id,
                claim.attempt,
                "quotaRejected",
                None,
                Some("quota_exceeded"),
                context.deadline,
            )
            .await?;
            if finalized {
                tracing::info!(
                    account_id = %context.account_id,
                    event_id = %context.event_id,
                    error = %error,
                    "push delivery skipped by quota"
                );
            }
            return Ok(false);
        }
        Err(error) => {
            release_claim_after_failure(state, claim.id).await;
            return Err(error);
        }
    }
    match claim_is_current(state, claim.id, context.deadline).await {
        Ok(true) => {}
        Ok(false) => {
            tracing::debug!(
                account_id = %context.account_id,
                event_id = %context.event_id,
                "push delivery lease changed before FCM send"
            );
            return Ok(false);
        }
        Err(error) => {
            release_claim_after_failure(state, claim.id).await;
            return Err(error);
        }
    }
    if Instant::now() >= context.send_deadline {
        return finalize_or_release(
            state,
            claim.id,
            claim.attempt,
            "failed",
            None,
            Some("deadline_exceeded"),
            context.deadline,
        )
        .await;
    }

    let message = FcmMessage {
        token: target.token.clone(),
        title: context.title.clone(),
        body: context.body.clone(),
        data: context.data.clone(),
        channel_id: context.channel_id.clone(),
    };
    let (attempt, result) =
        send_with_retry_until(state.fcm.as_ref(), message, context.send_deadline).await;
    match result {
        Ok(receipt) => {
            let finalized = finalize_or_release(
                state,
                claim.id,
                attempt,
                "delivered",
                Some(&receipt.message_id),
                None,
                context.deadline,
            )
            .await?;
            if !finalized {
                tracing::warn!(
                    account_id = %context.account_id,
                    event_id = %context.event_id,
                    device_id = %target.mobile_device_id,
                    "FCM delivered after push delivery lease changed"
                );
            }
            Ok(finalized)
        }
        Err(error) => {
            let error_code = error.code();
            let unregistered = matches!(&error, FcmError::Unregistered);
            let finalized = finalize_or_release(
                state,
                claim.id,
                attempt,
                "failed",
                None,
                Some(error_code),
                context.deadline,
            )
            .await?;
            if !finalized {
                tracing::warn!(
                    account_id = %context.account_id,
                    event_id = %context.event_id,
                    device_id = %target.mobile_device_id,
                    error_code,
                    "FCM failure arrived after push delivery lease changed"
                );
                return Ok(false);
            }
            if unregistered {
                match timeout_at(
                    context.deadline,
                    remove_unregistered_token(
                        state,
                        context.account_id,
                        &target.mobile_device_id,
                        &target.token,
                    ),
                )
                .await
                {
                    Ok(result) => result?,
                    Err(_) => tracing::warn!(
                        account_id = %context.account_id,
                        event_id = %context.event_id,
                        device_id = %target.mobile_device_id,
                        "timed out removing an unregistered FCM token"
                    ),
                }
            }
            tracing::warn!(
                account_id = %context.account_id,
                event_id = %context.event_id,
                device_id = %target.mobile_device_id,
                error_code,
                "FCM delivery failed"
            );
            Ok(true)
        }
    }
}

fn delivery_deadline_error() -> ApiError {
    ApiError::unavailable(
        "push_delivery_deadline",
        "Push delivery exceeded the request budget.",
    )
}

async fn claim_delivery_attempt(
    state: &AppState,
    context: &DeliveryContext,
    target: &DeliveryTarget,
) -> Result<DeliveryClaimOutcome, ApiError> {
    let now = chrono::Utc::now();
    let stale_before = now - chrono::TimeDelta::seconds(30);
    let claim = timeout_at(
        context.deadline,
        sqlx::query_as::<_, DeliveryClaim>(
            r#"
        WITH latest AS (
            SELECT id, attempt, status, created_at
            FROM delivery_attempts
            WHERE event_id = $1 AND mobile_device_id = $2
            ORDER BY attempt DESC, created_at DESC
            LIMIT 1
        ), reclaimed AS (
            UPDATE delivery_attempts
            SET id = $5,
                status = 'pending',
                provider_message_id = NULL,
                error_code = NULL,
                created_at = $3
            WHERE id = (
                SELECT id
                FROM latest
                WHERE status = 'retryable'
                   OR (status = 'pending' AND created_at < $4)
            )
              AND status IN ('pending', 'retryable')
              AND (status = 'retryable' OR created_at < $4)
            RETURNING id, attempt
        ), inserted AS (
            INSERT INTO delivery_attempts (
                id, event_id, account_id, mobile_device_id, attempt, status,
                provider_message_id, error_code, created_at
            )
            SELECT $5, $1, $6, $2, 1, 'pending', NULL, NULL, $3
            WHERE NOT EXISTS (
                SELECT 1 FROM latest WHERE status NOT IN ('pending', 'retryable')
            )
            AND NOT EXISTS (
                  SELECT 1 FROM latest WHERE status = 'pending' AND created_at >= $4
              )
              AND NOT EXISTS (SELECT 1 FROM reclaimed)
            ON CONFLICT (event_id, mobile_device_id, attempt) DO NOTHING
            RETURNING id, attempt
        )
        SELECT id, attempt FROM reclaimed
        UNION ALL
        SELECT id, attempt FROM inserted
        LIMIT 1
        "#,
        )
        .bind(context.event_id)
        .bind(&target.mobile_device_id)
        .bind(now)
        .bind(stale_before)
        .bind(Uuid::now_v7())
        .bind(context.account_id)
        .fetch_optional(&state.pool),
    )
    .await
    .map_err(|_| delivery_deadline_error())??;
    if let Some(claim) = claim {
        return Ok(DeliveryClaimOutcome::Claimed(claim));
    }
    let in_progress = timeout_at(
        context.deadline,
        sqlx::query_scalar::<_, bool>(
            "SELECT EXISTS(SELECT 1 FROM delivery_attempts WHERE event_id = $1 AND mobile_device_id = $2 AND status = 'pending' AND created_at >= $3)",
        )
        .bind(context.event_id)
        .bind(&target.mobile_device_id)
        .bind(stale_before)
        .fetch_one(&state.pool),
    )
    .await
    .map_err(|_| delivery_deadline_error())??;
    Ok(if in_progress {
        DeliveryClaimOutcome::InProgress
    } else {
        DeliveryClaimOutcome::Complete
    })
}

async fn claim_is_current(
    state: &AppState,
    claim_id: Uuid,
    deadline: Instant,
) -> Result<bool, ApiError> {
    timeout_at(
        deadline,
        sqlx::query_scalar::<_, bool>(
            "SELECT EXISTS(SELECT 1 FROM delivery_attempts WHERE id = $1 AND status = 'pending')",
        )
        .bind(claim_id)
        .fetch_one(&state.pool),
    )
    .await
    .map_err(|_| delivery_deadline_error())?
    .map_err(ApiError::from)
}

pub(crate) async fn run_bounded_deliveries<F>(tasks: Vec<F>) -> Vec<Result<bool, ApiError>>
where
    F: Future<Output = Result<bool, ApiError>> + Send + 'static,
{
    let mut pending = tasks.into_iter();
    let mut set = JoinSet::new();
    for _ in 0..MAX_PARALLEL_DELIVERIES {
        if let Some(task) = pending.next() {
            set.spawn(task);
        }
    }

    let mut results = Vec::new();
    while let Some(result) = set.join_next().await {
        results.push(match result {
            Ok(result) => result,
            Err(error) => Err(ApiError::internal(anyhow::anyhow!(
                "push delivery task failed: {error}"
            ))),
        });
        if let Some(task) = pending.next() {
            set.spawn(task);
        }
    }
    results
}

async fn finalize_attempt(
    state: &AppState,
    claim_id: Uuid,
    attempt: i32,
    status: &str,
    provider_message_id: Option<&str>,
    error_code: Option<&str>,
    deadline: Instant,
) -> Result<bool, ApiError> {
    let result = timeout_at(
        deadline,
        sqlx::query(
            r#"
        UPDATE delivery_attempts
        SET attempt = $2,
            status = $3,
            provider_message_id = $4,
            error_code = $5
        WHERE id = $1 AND status = 'pending'
        "#,
        )
        .bind(claim_id)
        .bind(attempt)
        .bind(status)
        .bind(provider_message_id)
        .bind(error_code)
        .execute(&state.pool),
    )
    .await
    .map_err(|_| delivery_deadline_error())??;
    if result.rows_affected() != 1 {
        tracing::debug!(
            claim_id = %claim_id,
            attempt,
            status,
            "push delivery finalize lost its lease"
        );
        return Ok(false);
    }
    Ok(true)
}

async fn finalize_or_release(
    state: &AppState,
    claim_id: Uuid,
    attempt: i32,
    status: &str,
    provider_message_id: Option<&str>,
    error_code: Option<&str>,
    deadline: Instant,
) -> Result<bool, ApiError> {
    match finalize_attempt(
        state,
        claim_id,
        attempt,
        status,
        provider_message_id,
        error_code,
        deadline,
    )
    .await
    {
        Ok(finalized) => Ok(finalized),
        Err(error) => {
            release_claim_after_failure(state, claim_id).await;
            Err(error)
        }
    }
}

async fn release_claim_after_failure(state: &AppState, claim_id: Uuid) {
    let result = timeout_at(
        Instant::now() + DELIVERY_DB_RESERVE,
        sqlx::query(
            "UPDATE delivery_attempts SET status = 'retryable' WHERE id = $1 AND status = 'pending'",
        )
        .bind(claim_id)
        .execute(&state.pool),
    )
    .await;
    match result {
        Ok(Ok(result)) if result.rows_affected() == 1 => {}
        Ok(Ok(_)) => tracing::debug!(
            claim_id = %claim_id,
            "push delivery claim was already released or reclaimed"
        ),
        Ok(Err(error)) => tracing::warn!(
            claim_id = %claim_id,
            error = %error,
            "failed to release push delivery claim after an error"
        ),
        Err(_) => tracing::warn!(
            claim_id = %claim_id,
            "timed out releasing push delivery claim after an error"
        ),
    }
}

#[cfg(test)]
#[path = "push_delivery_tests.rs"]
mod tests;
