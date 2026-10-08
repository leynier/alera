ALTER TABLE runtimes
    ADD COLUMN mcp_access TEXT NOT NULL DEFAULT 'off'
        CONSTRAINT runtimes_mcp_access_check CHECK (mcp_access IN ('off', 'read', 'full')),
    ADD COLUMN mobile_access_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN relay_granted_at TIMESTAMPTZ;

CREATE TABLE mcp_clients (
    id TEXT PRIMARY KEY,
    kind TEXT NOT NULL CONSTRAINT mcp_clients_kind_check
        CHECK (kind IN ('dynamic', 'metadata_document')),
    client_name TEXT NOT NULL,
    client_uri TEXT,
    redirect_uris TEXT[] NOT NULL,
    software_id TEXT,
    software_version TEXT,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    fetched_at TIMESTAMPTZ,
    last_used_at TIMESTAMPTZ
);
CREATE INDEX mcp_clients_last_used_idx ON mcp_clients (COALESCE(last_used_at, created_at));

CREATE TABLE web_logins (
    id UUID PRIMARY KEY,
    purpose TEXT NOT NULL CONSTRAINT web_logins_purpose_check CHECK (purpose IN ('mcp', 'device')),
    target_id UUID NOT NULL,
    provider TEXT NOT NULL,
    state_hash BYTEA NOT NULL UNIQUE,
    code_verifier TEXT NOT NULL,
    nonce TEXT,
    created_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ
);
CREATE INDEX web_logins_expiry_idx ON web_logins (expires_at);

CREATE TABLE mcp_authorization_requests (
    id UUID PRIMARY KEY,
    client_id TEXT NOT NULL REFERENCES mcp_clients(id) ON DELETE CASCADE,
    redirect_uri TEXT NOT NULL,
    state TEXT,
    code_challenge TEXT NOT NULL,
    scope TEXT NOT NULL,
    resource TEXT,
    account_id UUID REFERENCES accounts(id) ON DELETE CASCADE,
    consent_token_hash BYTEA,
    created_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ
);
CREATE INDEX mcp_authorization_requests_expiry_idx ON mcp_authorization_requests (expires_at);
CREATE INDEX mcp_authorization_requests_account_idx ON mcp_authorization_requests (account_id);
CREATE INDEX mcp_authorization_requests_client_idx ON mcp_authorization_requests (client_id);

CREATE TABLE mcp_grants (
    id UUID PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    client_id TEXT NOT NULL REFERENCES mcp_clients(id) ON DELETE CASCADE,
    client_name TEXT NOT NULL,
    redirect_uri TEXT NOT NULL,
    scopes TEXT NOT NULL,
    all_runtimes BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    last_used_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    revoke_reason TEXT
);
CREATE INDEX mcp_grants_account_idx ON mcp_grants (account_id);
CREATE INDEX mcp_grants_client_idx ON mcp_grants (client_id);

CREATE TABLE mcp_grant_runtimes (
    grant_id UUID NOT NULL REFERENCES mcp_grants(id) ON DELETE CASCADE,
    runtime_id TEXT NOT NULL REFERENCES runtimes(id) ON DELETE CASCADE,
    PRIMARY KEY (grant_id, runtime_id)
);
CREATE INDEX mcp_grant_runtimes_runtime_idx ON mcp_grant_runtimes (runtime_id);

CREATE TABLE mcp_authorization_codes (
    code_hash BYTEA PRIMARY KEY,
    grant_id UUID NOT NULL REFERENCES mcp_grants(id) ON DELETE CASCADE,
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    client_id TEXT NOT NULL,
    redirect_uri TEXT NOT NULL,
    code_challenge TEXT NOT NULL,
    resource TEXT,
    created_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ
);
CREATE INDEX mcp_authorization_codes_expiry_idx ON mcp_authorization_codes (expires_at);
CREATE INDEX mcp_authorization_codes_grant_idx ON mcp_authorization_codes (grant_id);
CREATE INDEX mcp_authorization_codes_account_idx ON mcp_authorization_codes (account_id);

CREATE TABLE device_authorizations (
    id UUID PRIMARY KEY,
    device_code_hash BYTEA NOT NULL UNIQUE,
    user_code TEXT NOT NULL UNIQUE,
    client_id TEXT NOT NULL,
    device_name TEXT NOT NULL,
    account_id UUID REFERENCES accounts(id) ON DELETE CASCADE,
    consent_token_hash BYTEA,
    status TEXT NOT NULL CONSTRAINT device_authorizations_status_check
        CHECK (status IN ('pending', 'approved', 'denied', 'consumed')),
    poll_interval_seconds INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    approved_at TIMESTAMPTZ,
    last_polled_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX device_authorizations_expiry_idx ON device_authorizations (expires_at);
CREATE INDEX device_authorizations_account_idx ON device_authorizations (account_id);

CREATE TABLE mcp_calls (
    id UUID PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    grant_id UUID REFERENCES mcp_grants(id) ON DELETE SET NULL,
    client_id TEXT NOT NULL,
    client_name TEXT NOT NULL,
    runtime_id TEXT NOT NULL,
    tool TEXT NOT NULL,
    access TEXT NOT NULL CONSTRAINT mcp_calls_access_check CHECK (access IN ('read', 'execute')),
    outcome TEXT CONSTRAINT mcp_calls_outcome_check
        CHECK (outcome IN ('ok', 'tool_error', 'runtime_offline', 'timeout', 'failed')),
    duration_ms INTEGER,
    created_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ
);
CREATE INDEX mcp_calls_created_at_idx ON mcp_calls (created_at);
CREATE INDEX mcp_calls_account_idx ON mcp_calls (account_id);
CREATE INDEX mcp_calls_grant_idx ON mcp_calls (grant_id);
