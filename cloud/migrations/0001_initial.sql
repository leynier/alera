CREATE TABLE accounts (
    id UUID PRIMARY KEY,
    primary_email TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    last_seen_at TIMESTAMPTZ NOT NULL,
    banned_at TIMESTAMPTZ,
    banned_reason TEXT,
    deleted_at TIMESTAMPTZ
);

CREATE TABLE account_identities (
    provider TEXT NOT NULL,
    provider_user_id TEXT NOT NULL,
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    email_verified BOOLEAN NOT NULL,
    linked_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (provider, provider_user_id)
);
CREATE INDEX account_identities_verified_email_idx
    ON account_identities (LOWER(email))
    WHERE email_verified;

CREATE TABLE auth_transactions (
    id UUID PRIMARY KEY,
    state_hash BYTEA NOT NULL,
    provider TEXT NOT NULL,
    purpose TEXT NOT NULL,
    account_id UUID REFERENCES accounts(id) ON DELETE CASCADE,
    refresh_family_id UUID,
    redirect_uri TEXT NOT NULL,
    code_challenge TEXT NOT NULL,
    nonce TEXT,
    client_id TEXT NOT NULL,
    client_kind TEXT NOT NULL,
    device_name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ
);

CREATE TABLE refresh_token_families (
    id UUID PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    client_id TEXT NOT NULL,
    client_kind TEXT NOT NULL,
    label TEXT NOT NULL,
    authenticated_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    last_used_at TIMESTAMPTZ NOT NULL,
    absolute_expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    revoke_reason TEXT
);
CREATE INDEX refresh_token_families_account_idx ON refresh_token_families(account_id);

ALTER TABLE auth_transactions
    ADD CONSTRAINT auth_transactions_refresh_family_fk
    FOREIGN KEY (refresh_family_id) REFERENCES refresh_token_families(id) ON DELETE SET NULL;

CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY,
    family_id UUID NOT NULL REFERENCES refresh_token_families(id) ON DELETE CASCADE,
    token_hash BYTEA NOT NULL UNIQUE,
    issued_at TIMESTAMPTZ NOT NULL,
    inactivity_expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    replaced_by_id UUID REFERENCES refresh_tokens(id),
    revoked_at TIMESTAMPTZ
);

CREATE TABLE runtimes (
    id TEXT PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    last_seen_at TIMESTAMPTZ NOT NULL,
    transferred_at TIMESTAMPTZ
);
CREATE INDEX runtimes_account_idx ON runtimes(account_id);

CREATE TABLE mobile_devices (
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    last_seen_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    PRIMARY KEY (account_id, id)
);

CREATE TABLE mobile_enrollments (
    id UUID PRIMARY KEY,
    code_hash BYTEA NOT NULL UNIQUE,
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    runtime_id TEXT NOT NULL REFERENCES runtimes(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL,
    device_name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    redeemed_at TIMESTAMPTZ
);

CREATE TABLE fcm_tokens (
    account_id UUID NOT NULL,
    mobile_device_id TEXT NOT NULL,
    token TEXT NOT NULL,
    token_hash BYTEA NOT NULL,
    platform TEXT NOT NULL,
    registered_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (account_id, mobile_device_id),
    FOREIGN KEY (account_id, mobile_device_id)
        REFERENCES mobile_devices(account_id, id) ON DELETE CASCADE
);
CREATE INDEX fcm_tokens_token_hash_idx ON fcm_tokens(token_hash);

CREATE TABLE push_subscriptions (
    account_id UUID NOT NULL,
    mobile_device_id TEXT NOT NULL,
    runtime_id TEXT NOT NULL REFERENCES runtimes(id) ON DELETE CASCADE,
    attention BOOLEAN NOT NULL,
    done BOOLEAN NOT NULL,
    terminal_exit BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (account_id, mobile_device_id, runtime_id),
    FOREIGN KEY (account_id, mobile_device_id)
        REFERENCES mobile_devices(account_id, id) ON DELETE CASCADE
);

CREATE TABLE runtime_events (
    id UUID PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    runtime_id TEXT NOT NULL REFERENCES runtimes(id) ON DELETE CASCADE,
    event_id TEXT NOT NULL,
    category TEXT NOT NULL,
    event_type TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    data JSONB NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    UNIQUE (runtime_id, event_id)
);

CREATE TABLE delivery_attempts (
    id UUID PRIMARY KEY,
    event_id UUID NOT NULL REFERENCES runtime_events(id) ON DELETE CASCADE,
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    mobile_device_id TEXT NOT NULL,
    attempt INTEGER NOT NULL,
    status TEXT NOT NULL,
    provider_message_id TEXT,
    error_code TEXT,
    created_at TIMESTAMPTZ NOT NULL,
    UNIQUE (event_id, mobile_device_id, attempt)
);

CREATE TABLE push_quota_daily (
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    day DATE NOT NULL,
    count INTEGER NOT NULL,
    PRIMARY KEY (account_id, day)
);

CREATE TABLE push_quota_hourly (
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    hour TIMESTAMPTZ NOT NULL,
    count INTEGER NOT NULL,
    PRIMARY KEY (account_id, hour)
);

CREATE TABLE push_quota_bursts (
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    window_start TIMESTAMPTZ NOT NULL,
    count INTEGER NOT NULL,
    PRIMARY KEY (account_id, window_start)
);

CREATE TABLE abuse_tombstones (
    id UUID PRIMARY KEY,
    subject_kind TEXT NOT NULL,
    subject_hash BYTEA NOT NULL,
    reason TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX abuse_tombstones_subject_idx ON abuse_tombstones(subject_kind, subject_hash);
