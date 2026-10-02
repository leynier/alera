-- no-transaction
CREATE INDEX CONCURRENTLY IF NOT EXISTS mobile_enrollments_expiry_idx
    ON mobile_enrollments (expires_at);
