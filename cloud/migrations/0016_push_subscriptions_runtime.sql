-- no-transaction
CREATE INDEX CONCURRENTLY IF NOT EXISTS push_subscriptions_runtime_idx
    ON push_subscriptions (runtime_id);
