/// Advertised once profile removal is impact-gated and requires explicit
/// confirmation. Older hosts delete directly, so callers must never fall back.
pub(crate) const RUNTIME_HOST_AGENT_PROFILE_REMOVAL_CAPABILITY: &str =
    "orchestrationAgentProfileRemovalV1";
