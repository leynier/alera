use super::*;

#[cfg(test)]
mod prompt_workspace_surface_tests {
    /// The phone's New Workspace from Prompt delegates to the runtime service
    /// once the hello list names it.
    #[test]
    fn mobile_may_run_new_workspace_from_prompt_on_the_runtime() {
        assert!(super::MOBILE_HELLO_CAPABILITIES.contains(&"promptWorkspaceServiceV1"));
        for request in [
            "workspace.promptStart.start",
            "workspace.promptStart.get",
            "workspace.promptStart.list",
            "workspace.promptStart.cancel",
            "workspace.promptStart.retryLaunch",
        ] {
            assert!(super::mobile_request_allowed(request), "{request}");
        }
    }
}

#[cfg(test)]
mod relay_renewal_tests {
    #[test]
    fn disabling_renewal_preserves_all_other_mobile_capabilities() {
        let enabled = super::mobile_hello_capabilities(true);
        let disabled = super::mobile_hello_capabilities(false);
        assert!(enabled.contains(&"relayAuthorizationRenewalV1"));
        assert!(!disabled.contains(&"relayAuthorizationRenewalV1"));
        assert_eq!(enabled.len(), disabled.len() + 1);
    }
}
