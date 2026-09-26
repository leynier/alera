use super::*;

#[test]
fn workflow_lifecycle_remains_desktop_only() {
    assert!(!MOBILE_HELLO_CAPABILITIES
        .contains(&crate::terminal_host::protocol::RUNTIME_HOST_WORKFLOW_LIFECYCLE_CAPABILITY));
    for verb in [
        "workflows.createProposal",
        "workflows.startCoordinator",
        "workflows.cancelProposal",
        "workflows.retryProposalCancellation",
        "workflows.controlExecution",
        "workflows.decide",
        "workflows.previewCleanup",
        "workflows.applyCleanup",
        "workflows.retryCleanup",
        "workflows.abandonCleanup",
    ] {
        assert!(!mobile_request_allowed(verb), "{verb}");
    }
}
