ALTER TABLE mcp_clients
    ADD COLUMN token_endpoint_auth_method TEXT NOT NULL DEFAULT 'none'
        CONSTRAINT mcp_clients_token_endpoint_auth_method_check
            CHECK (token_endpoint_auth_method IN ('none', 'private_key_jwt')),
    ADD COLUMN jwks_uri TEXT,
    ADD COLUMN token_endpoint_auth_signing_alg TEXT,
    ADD CONSTRAINT mcp_clients_private_key_jwt_jwks_check
        CHECK (token_endpoint_auth_method = 'none' OR jwks_uri IS NOT NULL);

CREATE TABLE mcp_client_assertions (
    client_id TEXT NOT NULL,
    jti_hash BYTEA NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (client_id, jti_hash)
);
CREATE INDEX mcp_client_assertions_expiry_idx ON mcp_client_assertions (expires_at);
