-- no-transaction
CREATE INDEX CONCURRENTLY IF NOT EXISTS delivery_attempts_account_idx
    ON delivery_attempts (account_id);
