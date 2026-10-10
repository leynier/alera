ALTER TABLE runtimes
    DROP CONSTRAINT runtimes_mcp_access_check,
    ADD CONSTRAINT runtimes_mcp_access_check
        CHECK (mcp_access IN ('off', 'read', 'full', 'admin'));

ALTER TABLE mcp_calls
    DROP CONSTRAINT mcp_calls_access_check,
    ADD CONSTRAINT mcp_calls_access_check
        CHECK (access IN ('read', 'execute', 'admin'));
