use super::*;

#[test]
fn mobile_allowlist_includes_workspace_mutations() {
    assert!(mobile_request_allowed("workspace.setPinned"));
    assert!(mobile_request_allowed("workspace.createManaged"));
    assert!(mobile_request_allowed("workspace.removeManaged"));
    assert!(mobile_request_allowed("workspaceRelation.link"));
    assert!(mobile_request_allowed("workspaceRelation.unlink"));
    assert!(mobile_request_allowed("tab.remove"));
    assert!(mobile_request_allowed("tab.rename"));
    assert!(mobile_request_allowed("mobile.runtimeSettings.get"));
    assert!(mobile_request_allowed("mobile.runtimeSettings.update"));
    assert!(mobile_request_allowed("agentQuota.snapshot"));
    assert!(mobile_request_allowed("agentQuota.fetchClaudeTui"));
    assert!(mobile_request_allowed("cliRegistration.status"));
    assert!(mobile_request_allowed("cliRegistration.install"));
    assert!(mobile_request_allowed("agentSkill.install"));
}

#[test]
fn mobile_allowlist_still_excludes_raw_and_admin_mutations() {
    assert!(!mobile_request_allowed("workspace.upsert"));
    assert!(!mobile_request_allowed("workspace.remove"));
    assert!(!mobile_request_allowed("tab.upsert"));
    assert!(!mobile_request_allowed("tab.removeForWorkspace"));
    assert!(!mobile_request_allowed("project.upsert"));
    assert!(!mobile_request_allowed("sshTarget.upsert"));
    assert!(!mobile_request_allowed("mobile.settings.update"));
    assert!(!mobile_request_allowed("runtimeMetadata.set"));
}

#[test]
fn mobile_allowlist_includes_high_level_project_management() {
    for request in [
        "hostDirectory.roots",
        "hostDirectory.list",
        "project.register",
        "project.rename",
        "project.remove.preview",
        "project.remove",
        "project.clone.start",
        "project.clone.list",
        "project.clone.cancel",
        "projectConfig.effective",
        "projectConfig.upsert",
        "projectConfig.remove",
    ] {
        assert!(
            mobile_request_allowed(request),
            "{request} should be allowed"
        );
    }
}

#[test]
fn terminal_read_cursor_advances_across_trimmed_scrollback() {
    assert_eq!(terminal_read_window(0, 4, None, 4), (0, 0, 4));
    assert_eq!(terminal_read_window(2, 6, Some(4), 4), (4, 4, 6));
    assert_eq!(terminal_read_window(8, 12, Some(4), 4), (4, 8, 12));
}

#[test]
fn terminal_text_pages_do_not_split_valid_utf8_scalars() {
    let bytes = "aé🙂z".as_bytes();
    let mut cursor = 0;
    let mut text = String::new();
    while cursor < bytes.len() as u64 {
        let (_, start, next) = terminal_read_window(0, bytes.len() as u64, Some(cursor), 1);
        let (start, next) = align_terminal_text_window(bytes, 0, start, next);
        assert!(next > cursor);
        text.push_str(std::str::from_utf8(&bytes[start as usize..next as usize]).unwrap());
        cursor = next;
    }
    assert_eq!(text, "aé🙂z");
    assert!(!text.contains('\u{fffd}'));
}

#[test]
fn terminal_text_window_skips_an_explicit_cursor_inside_a_scalar() {
    let bytes = "aéz".as_bytes();
    assert_eq!(align_terminal_text_window(bytes, 0, 2, 3), (3, 3));
    assert_eq!(align_terminal_text_window(&[0x80, b'a'], 0, 0, 1), (0, 1));
}

#[test]
fn mobile_hello_advertises_deferred_terminal_input() {
    // Without this the phone feature-detects a host that cannot split a prompt
    // from its Enter, falls back to one write, and agent TUIs read the trailing
    // CR inside the burst as a literal newline instead of a submit.
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_TERMINAL_DEFERRED_INPUT_CAPABILITY));
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_BINARY_FRAMES_CAPABILITY));
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_TERMINAL_DRIVER_CAPABILITY));
}

#[test]
fn soft_shutdown_busy_message_includes_agents() {
    assert_eq!(host_shutdown_busy_message(0, 0, 0), None);
    assert_eq!(
        host_shutdown_busy_message(2, 1, 0).as_deref(),
        Some(
            "Runtime host has 2 active agent(s), 1 active terminal session(s) and 0 active background job(s). Retry with --force to stop it."
        )
    );
    assert_eq!(
        host_shutdown_busy_message(1, 0, 0).as_deref(),
        Some(
            "Runtime host has 1 active agent(s), 0 active terminal session(s) and 0 active background job(s). Retry with --force to stop it."
        )
    );
}
