-- no-transaction
-- This index runs concurrently so normal API writes keep flowing while the
-- existing production table is indexed.
CREATE INDEX CONCURRENTLY IF NOT EXISTS auth_transactions_expiry_idx
    ON auth_transactions (expires_at);
