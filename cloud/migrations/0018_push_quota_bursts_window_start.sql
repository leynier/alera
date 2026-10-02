-- no-transaction
CREATE INDEX CONCURRENTLY IF NOT EXISTS push_quota_bursts_window_start_idx
    ON push_quota_bursts (window_start);
