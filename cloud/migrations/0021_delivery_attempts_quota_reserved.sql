ALTER TABLE delivery_attempts
    ADD COLUMN quota_reserved BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE delivery_attempts
    ALTER COLUMN quota_reserved SET DEFAULT FALSE;
