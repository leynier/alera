CREATE TABLE relay_identities (
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    client_kind TEXT NOT NULL,
    client_id TEXT NOT NULL,
    public_key BYTEA NOT NULL,
    key_version INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    PRIMARY KEY (account_id, client_kind, client_id)
);
CREATE INDEX relay_identities_runtime_idx
    ON relay_identities (account_id, client_kind, revoked_at);

ALTER TABLE relay_identities
    ADD CONSTRAINT relay_identities_client_kind_check
    CHECK (client_kind IN ('runtime', 'mobile'));

ALTER TABLE relay_identities
    ADD CONSTRAINT relay_identities_key_version_check
    CHECK (key_version > 0);

ALTER TABLE relay_identities
    ADD CONSTRAINT relay_identities_key_length_check
    CHECK (octet_length(public_key) = 32);
