-- no-transaction
CREATE INDEX CONCURRENTLY IF NOT EXISTS mobile_enrollments_account_idx
    ON mobile_enrollments (account_id);
