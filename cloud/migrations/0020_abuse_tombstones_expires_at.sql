-- no-transaction
CREATE INDEX CONCURRENTLY IF NOT EXISTS abuse_tombstones_expires_at_idx
    ON abuse_tombstones (expires_at);
