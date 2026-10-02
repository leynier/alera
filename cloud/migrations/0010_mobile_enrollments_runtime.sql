-- no-transaction
CREATE INDEX CONCURRENTLY IF NOT EXISTS mobile_enrollments_runtime_idx
    ON mobile_enrollments (runtime_id);
