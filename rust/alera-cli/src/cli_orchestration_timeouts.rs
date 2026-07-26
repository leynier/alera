use crate::terminal_host::protocol::{
    ORCHESTRATION_ACCEPTANCE_TIMEOUT_MS, ORCHESTRATION_MAX_WAIT_TIMEOUT_MS,
};

/// Parse-time validation for the `--timeout-ms` flags.
///
/// The host caps both kinds of timeout and applies the cap silently, so a
/// caller that asks for more only finds out when the call returns early. These
/// turn that into an immediate error at the flag instead of a puzzle minutes
/// later, and keeping them side by side is what keeps them consistent.
fn parse_timeout_ms(value: &str, ceiling: u64) -> Result<u64, String> {
    let timeout = value
        .parse::<u64>()
        .map_err(|_| "timeout must be an integer number of milliseconds".to_string())?;
    if !(1..=ceiling).contains(&timeout) {
        return Err(format!(
            "timeout must be between 1 and {ceiling} milliseconds"
        ));
    }
    Ok(timeout)
}

/// Bounded by how long the host will wait for a spawned agent to accept.
pub(crate) fn parse_agent_spawn_timeout_ms(value: &str) -> Result<u64, String> {
    parse_timeout_ms(value, ORCHESTRATION_ACCEPTANCE_TIMEOUT_MS)
}

/// Bounded by how long the host will hold a parked wait open.
pub(crate) fn parse_wait_timeout_ms(value: &str) -> Result<u64, String> {
    parse_timeout_ms(value, ORCHESTRATION_MAX_WAIT_TIMEOUT_MS)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn agent_spawn_timeout_respects_host_acceptance_limit() {
        assert_eq!(parse_agent_spawn_timeout_ms("1").unwrap(), 1);
        assert_eq!(
            parse_agent_spawn_timeout_ms(&ORCHESTRATION_ACCEPTANCE_TIMEOUT_MS.to_string()).unwrap(),
            ORCHESTRATION_ACCEPTANCE_TIMEOUT_MS
        );
        assert!(parse_agent_spawn_timeout_ms("0").is_err());
        assert!(parse_agent_spawn_timeout_ms(
            &(ORCHESTRATION_ACCEPTANCE_TIMEOUT_MS + 1).to_string()
        )
        .is_err());
    }

    #[test]
    fn a_wait_timeout_within_the_host_ceiling_is_accepted() {
        assert_eq!(parse_wait_timeout_ms("1").unwrap(), 1);
        assert_eq!(
            parse_wait_timeout_ms(&ORCHESTRATION_MAX_WAIT_TIMEOUT_MS.to_string()).unwrap(),
            ORCHESTRATION_MAX_WAIT_TIMEOUT_MS
        );
    }

    #[test]
    fn a_wait_timeout_the_host_would_clamp_is_refused() {
        // The case this exists for: asking for an hour and being answered at
        // ten minutes used to look like the wait had genuinely expired.
        let error = parse_wait_timeout_ms("3600000").unwrap_err();

        assert!(error.contains(&ORCHESTRATION_MAX_WAIT_TIMEOUT_MS.to_string()));
    }

    #[test]
    fn a_nonsense_timeout_is_refused() {
        assert!(parse_wait_timeout_ms("0").is_err());
        assert!(parse_wait_timeout_ms("-1").is_err());
        assert!(parse_wait_timeout_ms("soon").is_err());
    }
}
