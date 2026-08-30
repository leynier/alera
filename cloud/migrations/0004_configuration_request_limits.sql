CREATE TABLE configuration_request_limits (
    account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    operation text NOT NULL CHECK (operation IN ('read', 'write')),
    window_started_at timestamptz NOT NULL DEFAULT now(),
    request_count integer NOT NULL DEFAULT 1,
    PRIMARY KEY (account_id, operation)
);
