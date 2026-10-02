-- no-transaction
CREATE INDEX CONCURRENTLY IF NOT EXISTS runtime_events_account_idx
    ON runtime_events (account_id);
