-- no-transaction
CREATE INDEX CONCURRENTLY IF NOT EXISTS push_quota_hourly_hour_idx
    ON push_quota_hourly (hour);
