-- no-transaction
CREATE INDEX CONCURRENTLY IF NOT EXISTS push_subscriptions_account_runtime_idx
    ON push_subscriptions (account_id, runtime_id, mobile_device_id);
