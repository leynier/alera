-- no-transaction
CREATE INDEX CONCURRENTLY IF NOT EXISTS auth_transactions_refresh_family_idx
    ON auth_transactions (refresh_family_id);
