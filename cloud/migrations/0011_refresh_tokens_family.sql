-- no-transaction
CREATE INDEX CONCURRENTLY IF NOT EXISTS refresh_tokens_family_idx
    ON refresh_tokens (family_id);
