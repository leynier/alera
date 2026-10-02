-- no-transaction
CREATE INDEX CONCURRENTLY IF NOT EXISTS auth_transactions_account_idx
    ON auth_transactions (account_id);
