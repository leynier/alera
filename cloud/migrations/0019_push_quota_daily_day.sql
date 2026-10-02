-- no-transaction
CREATE INDEX CONCURRENTLY IF NOT EXISTS push_quota_daily_day_idx
    ON push_quota_daily (day);
