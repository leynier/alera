/// Advertised once profile removal is impact-gated and requires explicit
/// confirmation. Older hosts delete directly, so callers must never fall back.
pub(crate) const RUNTIME_HOST_AGENT_PROFILE_REMOVAL_CAPABILITY: &str =
    "orchestrationAgentProfileRemovalV1";

/// Advertised once agent-profile launch receipts are durable and scoped to the
/// authenticated caller and workspace.
pub(crate) const RUNTIME_HOST_AGENT_PROFILE_LAUNCH_IDEMPOTENCY_CAPABILITY: &str =
    "agentProfileLaunchIdempotencyV1";
