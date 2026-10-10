-- Runtime domain events forwarded for webhooks and MCP Events. Events are kept for 24 hours.
CREATE TABLE domain_events (
    id UUID PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    runtime_id TEXT NOT NULL,
    event_id TEXT NOT NULL,
    seq BIGINT NOT NULL,
    kind TEXT NOT NULL,
    workspace_id TEXT,
    project_id TEXT,
    data JSONB NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL,
    received_at TIMESTAMPTZ NOT NULL,
    fanned_out_at TIMESTAMPTZ,
    CONSTRAINT domain_events_runtime_event_key UNIQUE (runtime_id, event_id)
);
CREATE INDEX domain_events_received_idx ON domain_events (received_at);
CREATE INDEX domain_events_fanout_idx ON domain_events (received_at) WHERE fanned_out_at IS NULL;
CREATE INDEX domain_events_account_idx ON domain_events (account_id, received_at);

-- Webhooks created by a signed-in runtime and MCP Events subscriptions bound to an MCP grant.
CREATE TABLE event_subscriptions (
    id TEXT PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    target_kind TEXT NOT NULL CONSTRAINT event_subscriptions_target_kind_check
        CHECK (target_kind IN ('webhook', 'mcp_events')),
    callback_url TEXT NOT NULL,
    secret_ciphertext TEXT NOT NULL,
    previous_secret_ciphertext TEXT,
    previous_secret_until TIMESTAMPTZ,
    kinds TEXT[] NOT NULL,
    runtime_ids TEXT[] NOT NULL DEFAULT '{}',
    all_runtimes BOOLEAN NOT NULL,
    status TEXT NOT NULL CONSTRAINT event_subscriptions_status_check
        CHECK (status IN ('active', 'stopped', 'revoked', 'expired')),
    refresh_before TIMESTAMPTZ,
    owner_grant_id UUID REFERENCES mcp_grants(id) ON DELETE CASCADE,
    filter JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_by_runtime_id TEXT,
    verified_at TIMESTAMPTZ,
    last_delivery_at TIMESTAMPTZ,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT event_subscriptions_owner_check
        CHECK (target_kind = 'webhook' OR owner_grant_id IS NOT NULL)
);
CREATE INDEX event_subscriptions_account_idx ON event_subscriptions (account_id, status);
CREATE INDEX event_subscriptions_grant_idx ON event_subscriptions (owner_grant_id);

-- One delivery per subscription and event. `next_attempt_at` doubles as the lease
-- deadline while a worker holds the row in `sending`.
CREATE TABLE event_deliveries (
    id UUID PRIMARY KEY,
    subscription_id TEXT NOT NULL REFERENCES event_subscriptions(id) ON DELETE CASCADE,
    event_id UUID NOT NULL REFERENCES domain_events(id) ON DELETE CASCADE,
    status TEXT NOT NULL CONSTRAINT event_deliveries_status_check
        CHECK (status IN ('pending', 'sending', 'delivered', 'stopped', 'dead')),
    attempts INTEGER NOT NULL DEFAULT 0,
    next_attempt_at TIMESTAMPTZ NOT NULL,
    lease_until TIMESTAMPTZ,
    last_status INTEGER,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL,
    delivered_at TIMESTAMPTZ,
    CONSTRAINT event_deliveries_subscription_event_key UNIQUE (subscription_id, event_id)
);
CREATE INDEX event_deliveries_due_idx ON event_deliveries (next_attempt_at)
    WHERE status IN ('pending', 'sending');
CREATE INDEX event_deliveries_event_idx ON event_deliveries (event_id);
