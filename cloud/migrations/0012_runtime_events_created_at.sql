-- no-transaction
CREATE INDEX CONCURRENTLY IF NOT EXISTS runtime_events_created_at_idx
    ON runtime_events (created_at);
