use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

use crate::{config::LimitsConfig, error::ApiError};

pub async fn reserve_push_delivery(
    pool: &PgPool,
    claim_id: Uuid,
    account_id: Uuid,
    limits: &LimitsConfig,
) -> Result<bool, ApiError> {
    let now = Utc::now();
    let hour = truncated(now, 60 * 60)?;
    let burst = truncated(now, 60)?;
    let mut transaction = pool.begin().await?;
    let Some((status, quota_reserved)) = sqlx::query_as::<_, (String, bool)>(
        "SELECT status, quota_reserved FROM delivery_attempts WHERE id = $1 FOR UPDATE",
    )
    .bind(claim_id)
    .fetch_optional(&mut *transaction)
    .await?
    else {
        return Ok(false);
    };
    if status != "pending" {
        return Ok(false);
    }
    if quota_reserved {
        return Ok(true);
    }
    let daily = sqlx::query_scalar::<_, i32>(
        r#"
        INSERT INTO push_quota_daily (account_id, day, count)
        VALUES ($1, $2, 1)
        ON CONFLICT (account_id, day) DO UPDATE
        SET count = push_quota_daily.count + 1
        WHERE push_quota_daily.count < $3
        RETURNING count
        "#,
    )
    .bind(account_id)
    .bind(now.date_naive())
    .bind(limits.push_daily)
    .fetch_optional(&mut *transaction)
    .await?;
    if daily.is_none() {
        return Err(quota_error("daily_push_quota"));
    }
    let hourly = sqlx::query_scalar::<_, i32>(
        r#"
        INSERT INTO push_quota_hourly (account_id, hour, count)
        VALUES ($1, $2, 1)
        ON CONFLICT (account_id, hour) DO UPDATE
        SET count = push_quota_hourly.count + 1
        WHERE push_quota_hourly.count < $3
        RETURNING count
        "#,
    )
    .bind(account_id)
    .bind(hour)
    .bind(limits.push_hourly)
    .fetch_optional(&mut *transaction)
    .await?;
    if hourly.is_none() {
        return Err(quota_error("hourly_push_quota"));
    }
    let burst_count = sqlx::query_scalar::<_, i32>(
        r#"
        INSERT INTO push_quota_bursts (account_id, window_start, count)
        VALUES ($1, $2, 1)
        ON CONFLICT (account_id, window_start) DO UPDATE
        SET count = push_quota_bursts.count + 1
        WHERE push_quota_bursts.count < $3
        RETURNING count
        "#,
    )
    .bind(account_id)
    .bind(burst)
    .bind(limits.push_burst)
    .fetch_optional(&mut *transaction)
    .await?;
    if burst_count.is_none() {
        return Err(quota_error("burst_push_quota"));
    }
    let marked = sqlx::query(
        "UPDATE delivery_attempts SET quota_reserved = TRUE WHERE id = $1 AND status = 'pending' AND NOT quota_reserved",
    )
    .bind(claim_id)
    .execute(&mut *transaction)
    .await?;
    if marked.rows_affected() != 1 {
        return Ok(false);
    }
    transaction.commit().await?;
    Ok(true)
}

fn truncated(value: DateTime<Utc>, seconds: i64) -> Result<DateTime<Utc>, ApiError> {
    let timestamp = value.timestamp() - value.timestamp().rem_euclid(seconds);
    DateTime::from_timestamp(timestamp, 0)
        .ok_or_else(|| ApiError::internal(anyhow::anyhow!("timestamp truncation failed")))
}

fn quota_error(code: &'static str) -> ApiError {
    ApiError::too_many(code, "The account push delivery quota has been reached.")
}

#[cfg(test)]
mod tests {
    use chrono::{Timelike, Utc};

    use super::truncated;

    #[test]
    fn truncates_quota_windows() {
        let minute = truncated(Utc::now(), 60);
        assert!(minute.is_ok());
        let minute = match minute {
            Ok(value) => value,
            Err(error) => panic!("unexpected truncation error: {error}"),
        };
        assert_eq!(minute.second(), 0);
    }
}
