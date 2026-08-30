CREATE TABLE configuration_heads (
    account_id uuid PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    revision bigint NOT NULL DEFAULT 0
);
CREATE TABLE configuration_revisions (
    account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    revision bigint NOT NULL,
    operation_id uuid NOT NULL,
    request_hash text NOT NULL,
    document jsonb NOT NULL,
    device_name text NOT NULL,
    client_id text NOT NULL,
    summary text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (account_id, revision),
    UNIQUE (account_id, operation_id)
);
