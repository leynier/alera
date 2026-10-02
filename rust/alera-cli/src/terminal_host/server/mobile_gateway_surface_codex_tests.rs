use super::*;

#[test]
fn advertises_and_allows_mobile_codex_file_surfaces() {
    assert!(
        MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_MOBILE_CODEX_WORKSPACE_FILES_CAPABILITY)
    );
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_MOBILE_PROMPT_FILE_UPLOAD_CAPABILITY));
    assert!(
        MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_MOBILE_PROMPT_ATTACHMENT_READ_CAPABILITY)
    );
    for request in [
        "mobile.workspaceQuickOpen.start",
        "mobile.workspaceQuickOpen.search",
        "mobile.workspaceQuickOpen.stop",
        "mobile.workspaceFile.read",
        "mobile.promptFile.start",
        "mobile.promptFile.chunk",
        "mobile.promptFile.complete",
        "mobile.promptFile.cancel",
        "mobile.promptAttachment.read",
    ] {
        assert!(mobile_request_allowed(request), "{request}");
    }
}

#[test]
fn advertises_and_allows_mobile_workspace_panels() {
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_MOBILE_EXPLORER_CAPABILITY));
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_MOBILE_WORKSPACE_SEARCH_CAPABILITY));
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_MOBILE_WORKSPACE_REPLACE_CAPABILITY));
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_MOBILE_SOURCE_CONTROL_CAPABILITY));
    assert!(MOBILE_HELLO_CAPABILITIES.contains(
        &crate::terminal_host::protocol::RUNTIME_HOST_MOBILE_SOURCE_CONTROL_ROOT_CAPABILITY
    ));
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_MOBILE_PULL_REQUEST_CAPABILITY));
    assert!(
        MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_MOBILE_PULL_REQUEST_SUMMARIES_CAPABILITY)
    );
    for request in [
        "mobile.workspaceExplorer.list",
        "mobile.workspaceSearch.run",
        "mobile.workspaceSearch.replace",
        "mobile.workspaceSearch.cancel",
        "mobile.git.status",
        "mobile.git.diff",
        "mobile.pullRequest.snapshot",
        "mobile.pullRequest.summaries",
    ] {
        assert!(mobile_request_allowed(request), "{request}");
    }
}

#[test]
fn advertises_and_allows_pull_request_actions_but_not_raw_link_writes() {
    assert!(MOBILE_HELLO_CAPABILITIES.contains(
        &crate::terminal_host::protocol::RUNTIME_HOST_MOBILE_PULL_REQUEST_ACTIONS_CAPABILITY
    ));
    for request in [
        "mobile.pullRequest.comment",
        "mobile.pullRequest.commentUpdate",
        "mobile.pullRequest.merge",
        "mobile.pullRequest.draftStatus",
        "mobile.pullRequest.close",
        "mobile.pullRequest.link",
        "mobile.pullRequest.unlink",
        "mobile.pullRequest.create",
    ] {
        assert!(mobile_request_allowed(request), "{request}");
    }
    assert!(!mobile_request_allowed("linkedReview.upsert"));
    assert!(!mobile_request_allowed("linkedReview.remove"));
    assert!(
        MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_AI_ASSIST_PULL_REQUEST_DETAILS_CAPABILITY)
    );
    assert!(mobile_request_allowed("aiText.pullRequestDetails.generate"));
    assert!(MOBILE_HELLO_CAPABILITIES.contains(
        &crate::terminal_host::protocol::RUNTIME_HOST_MOBILE_PULL_REQUEST_SHIP_CAPABILITY
    ));
    assert!(mobile_request_allowed("mobile.pullRequest.ship"));
}

#[test]
fn advertises_remote_workspaces_and_names_hosts_without_exposing_them() {
    assert!(MOBILE_HELLO_CAPABILITIES.contains(
        &crate::terminal_host::protocol::RUNTIME_HOST_MOBILE_REMOTE_WORKSPACES_CAPABILITY
    ));
    assert!(mobile_request_allowed("mobile.hosts.list"));
    // The full target record says how to reach a host, and running a tool
    // on one is a desktop power.
    for request in ["sshTarget.list", "host.process.run", "project.hosts.add"] {
        assert!(!mobile_request_allowed(request), "{request}");
    }
}

#[test]
fn advertises_and_allows_linked_issues() {
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_LINKED_ISSUES_CAPABILITY));
    for request in [
        "linkedIssue.list",
        "linkedIssue.find",
        "linkedIssue.link",
        "linkedIssue.refresh",
        "linkedIssue.remove",
        "issue.fetch",
    ] {
        assert!(mobile_request_allowed(request), "{request}");
    }
}

#[test]
fn advertises_and_allows_pull_request_watch_execution() {
    assert!(
        MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_PULL_REQUEST_WATCH_EXECUTION_CAPABILITY)
    );
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_PULL_REQUEST_WATCH_CAPABILITY));
    for request in ["pullRequestWatch.list", "pullRequestWatch.find"] {
        assert!(mobile_request_allowed(request), "{request}");
    }
    assert!(mobile_request_allowed("pullRequestWatch.start"));
    assert!(mobile_request_allowed("pullRequestWatch.stop"));
}

#[test]
fn advertises_and_allows_mobile_source_control_writes() {
    assert!(
        MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_MOBILE_SOURCE_CONTROL_WRITES_CAPABILITY)
    );
    for request in super::super::mobile_source_control_write_requests::MOBILE_GIT_WRITE_REQUESTS
        .iter()
        .chain(&["mobile.git.branches"])
    {
        assert!(mobile_request_allowed(request), "{request}");
    }
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_AI_ASSIST_COMMIT_MESSAGE_CAPABILITY));
    assert!(mobile_request_allowed("aiText.commitMessage.generate"));
}

#[test]
fn advertises_and_allows_speech_capabilities() {
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_AI_DICTATION_BACKENDS_CAPABILITY));
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_REMOTE_AI_DICTATION_CAPABILITY));
    assert!(mobile_request_allowed("mobile.aiDictation.capabilities"));
}
