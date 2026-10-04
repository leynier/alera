use super::is_non_retryable_reason;

#[test]
fn continuity_and_authentication_failures_are_not_retryable() {
    for reason in [
        "automation existing tab is missing",
        "automation conversation continuity cannot be proven",
        "remote interactive authentication required",
        "SSH target is missing: remote",
    ] {
        assert!(is_non_retryable_reason(reason), "{reason}");
    }
    assert!(!is_non_retryable_reason("agent process exited with code 1"));
}
