use sqlx::Row;
use uuid::Uuid;

const CODEX_RESET_ATTEMPT_SCHEMA: &str = "CREATE TABLE IF NOT EXISTS codexResetCreditAttempts (
    accountId TEXT PRIMARY KEY,
    offerRevision TEXT NOT NULL,
    idempotencyKey TEXT NOT NULL,
    state TEXT NOT NULL,
    outcome TEXT,
    updatedAt INTEGER NOT NULL
);";

#[derive(Debug)]
enum PreparedCodexReset {
    Pending { idempotency_key: String },
    Settled { outcome: String },
}

pub(crate) async fn consume_codex_reset_credit(
    store: &RuntimeStore,
    payload: Value,
) -> Result<Value> {
    let expected_revision = payload
        .get("offerRevision")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow!("offerRevision must be a non-empty string"))?;
    let (auth, current_snapshot) = fetch_codex_reset_offer().await?;
    let credits = current_snapshot
        .rate_limit_reset_credits
        .as_ref()
        .ok_or_else(|| anyhow!("Codex reset offer is unavailable"))?;
    if credits.offer_revision != expected_revision {
        return Ok(json!({
            "status": "rejected",
            "reason": "offerChanged",
            "snapshot": current_snapshot,
        }));
    }
    if !credits.can_consume {
        return Ok(json!({
            "status": "rejected",
            "reason": "noCredit",
            "snapshot": current_snapshot,
        }));
    }
    let account_id = auth
        .account_id
        .as_deref()
        .ok_or_else(|| anyhow!("Codex account identity is unavailable"))?;
    let prepared = prepare_codex_reset_attempt(store, account_id, expected_revision).await?;
    let outcome = match prepared {
        PreparedCodexReset::Settled { outcome } => outcome,
        PreparedCodexReset::Pending { idempotency_key } => {
            let outcome = post_codex_reset_credit(&auth, &idempotency_key).await?;
            settle_codex_reset_attempt(store, account_id, &idempotency_key, &outcome).await?
        }
    };
    let refreshed = fetch_codex_via_backend()
        .await
        .ok()
        .flatten()
        .unwrap_or_else(|| current_snapshot.clone());
    Ok(json!({
        "status": "consumed",
        "outcome": outcome,
        "snapshot": refreshed,
    }))
}

async fn prepare_codex_reset_attempt(
    store: &RuntimeStore,
    account_id: &str,
    offer_revision: &str,
) -> Result<PreparedCodexReset> {
    sqlx::query(CODEX_RESET_ATTEMPT_SCHEMA)
        .execute(store.pool())
        .await
        .context("Could not initialize Codex reset attempt storage")?;
    let mut connection = store
        .pool()
        .acquire()
        .await
        .context("Could not open Codex reset attempt storage")?;
    sqlx::query("BEGIN IMMEDIATE")
        .execute(&mut *connection)
        .await
        .context("Could not lock Codex reset attempt storage")?;
    let result: Result<PreparedCodexReset> = async {
        let existing = sqlx::query(
            "SELECT offerRevision, idempotencyKey, state, outcome
             FROM codexResetCreditAttempts WHERE accountId = ?",
        )
        .bind(account_id)
        .fetch_optional(&mut *connection)
        .await?;
        if let Some(row) = existing {
            let state: String = row.try_get("state")?;
            let existing_revision: String = row.try_get("offerRevision")?;
            let idempotency_key: String = row.try_get("idempotencyKey")?;
            if state == "pending" {
                return Ok(PreparedCodexReset::Pending { idempotency_key });
            }
            if state == "settled" && existing_revision == offer_revision {
                let outcome = row
                    .try_get::<Option<String>, _>("outcome")?
                    .ok_or_else(|| anyhow!("Settled Codex reset attempt is missing its outcome"))?;
                return Ok(PreparedCodexReset::Settled { outcome });
            }
        }
        let idempotency_key = Uuid::new_v4().to_string();
        sqlx::query(
            "INSERT INTO codexResetCreditAttempts
                (accountId, offerRevision, idempotencyKey, state, outcome, updatedAt)
             VALUES (?, ?, ?, 'pending', NULL, ?)
             ON CONFLICT(accountId) DO UPDATE SET
                offerRevision = excluded.offerRevision,
                idempotencyKey = excluded.idempotencyKey,
                state = 'pending',
                outcome = NULL,
                updatedAt = excluded.updatedAt",
        )
        .bind(account_id)
        .bind(offer_revision)
        .bind(&idempotency_key)
        .bind(now_millis())
        .execute(&mut *connection)
        .await?;
        Ok(PreparedCodexReset::Pending { idempotency_key })
    }
    .await;
    match result {
        Ok(prepared) => {
            sqlx::query("COMMIT")
                .execute(&mut *connection)
                .await
                .context("Could not commit Codex reset attempt")?;
            Ok(prepared)
        }
        Err(error) => {
            let _ = sqlx::query("ROLLBACK").execute(&mut *connection).await;
            Err(error).context("Could not persist Codex reset attempt")
        }
    }
}

async fn settle_codex_reset_attempt(
    store: &RuntimeStore,
    account_id: &str,
    idempotency_key: &str,
    outcome: &str,
) -> Result<String> {
    let updated = sqlx::query(
        "UPDATE codexResetCreditAttempts
         SET state = 'settled', outcome = ?, updatedAt = ?
         WHERE accountId = ? AND idempotencyKey = ? AND state = 'pending'",
    )
    .bind(outcome)
    .bind(now_millis())
    .bind(account_id)
    .bind(idempotency_key)
    .execute(store.pool())
    .await
    .context("Could not settle Codex reset attempt")?;
    if updated.rows_affected() == 1 {
        return Ok(outcome.to_string());
    }
    let existing = sqlx::query(
        "SELECT outcome FROM codexResetCreditAttempts
         WHERE accountId = ? AND idempotencyKey = ? AND state = 'settled'",
    )
    .bind(account_id)
    .bind(idempotency_key)
    .fetch_optional(store.pool())
    .await
    .context("Could not verify the settled Codex reset attempt")?;
    existing
        .and_then(|row| row.try_get::<Option<String>, _>("outcome").ok().flatten())
        .ok_or_else(|| anyhow!("Codex reset attempt changed before its outcome could be stored"))
}
