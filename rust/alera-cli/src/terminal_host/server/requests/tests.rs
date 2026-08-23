use super::*;
use crate::terminal_host::server::mobile_gateway_surface::mobile_request_allowed;

use crate::mobile_access::MOBILE_PROTOCOL_VERSION;
use crate::terminal_host::server::mobile_gateway_surface::MOBILE_HELLO_CAPABILITIES;
use crate::terminal_host::server::mobile_hello_requests::MobileHelloRequest;
// Only the hello-capabilities test needs this one, and importing it in the
// parent would leave it unused in every non-test build.
use crate::terminal_host::protocol::{
    PROTOCOL_VERSION, RUNTIME_HOST_ACCOUNT_CAPABILITY,
    RUNTIME_HOST_AGENT_PROFILE_PROMPT_LAUNCH_CAPABILITY,
    RUNTIME_HOST_AI_DICTATION_MODELS_CAPABILITY, RUNTIME_HOST_AI_TEXT_SPEECH_MESSAGE_CAPABILITY,
    RUNTIME_HOST_AI_TEXT_WORKSPACE_IDENTITY_CAPABILITY, RUNTIME_HOST_BINARY_FRAMES_CAPABILITY,
    RUNTIME_HOST_CLOUD_PUSH_CAPABILITY, RUNTIME_HOST_CODEX_CHAT_CAPABILITY,
    RUNTIME_HOST_CODEX_GOALS_CAPABILITY, RUNTIME_HOST_CODEX_RESET_CREDITS_CAPABILITY,
    RUNTIME_HOST_CODEX_TURN_POLICY_CAPABILITY, RUNTIME_HOST_MOBILE_CLOUD_ENROLLMENT_CAPABILITY,
    RUNTIME_HOST_MOBILE_PROMPT_IMAGE_UPLOAD_CAPABILITY, RUNTIME_HOST_RESTART_CAPABILITY,
    RUNTIME_HOST_TERMINAL_DEFERRED_INPUT_CAPABILITY, RUNTIME_HOST_TERMINAL_DRIVER_CAPABILITY,
    RUNTIME_HOST_TERMINAL_RESTART_CAPABILITY,
};

#[tokio::test]
async fn soft_shutdown_counts_a_runtime_mutation_without_an_emulator_manager() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut receiver) = crate::terminal_host::client::ClientHandle::test_channels();
    let mut actor = crate::terminal_host::server::actor_test_harness::test_actor(
        &dir,
        std::collections::HashMap::from([(
            1,
            crate::terminal_host::server::actor_test_harness::local_client(handle),
        )]),
        std::collections::HashMap::new(),
    )
    .await;
    actor.emulators = None;
    let (inbox, mut inbox_receiver) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;

    actor
        .handle_line(
            1,
            serde_json::json!({
                "id": 1,
                "type": "tab.remove",
                "payload": {"id": "missing-tab"},
            })
            .to_string(),
        )
        .await;
    assert_eq!(actor.emulator_requests.outstanding(), 1);
    actor
        .handle_line(
            1,
            serde_json::json!({
                "id": 2,
                "type": "host.shutdown",
                "payload": {},
            })
            .to_string(),
        )
        .await;

    let response = receiver.recv().await.unwrap().as_json().unwrap();
    assert_eq!(response["id"], 2);
    assert_eq!(response["ok"], false);
    assert!(!response["error"].as_str().unwrap().is_empty());
    while let Ok(command) = inbox_receiver.try_recv() {
        assert!(!matches!(command, ServerCommand::RequestedShutdown));
    }
}

#[tokio::test]
async fn stale_codex_tab_removal_does_not_depend_on_remote_cleanup() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut receiver) = crate::terminal_host::client::ClientHandle::test_channels();
    let mut actor = crate::terminal_host::server::actor_test_harness::test_actor(
        &dir,
        std::collections::HashMap::from([(
            1,
            crate::terminal_host::server::actor_test_harness::local_client(handle),
        )]),
        std::collections::HashMap::new(),
    )
    .await;
    let now = chrono::Utc::now();
    actor
        .runtime_store
        .upsert_workspace_tab(alera_core::runtime::WorkspaceTabRecord {
            id: "stale-codex-tab".to_string(),
            workspace_id: "missing-workspace".to_string(),
            kind: crate::terminal_host::protocol::CODEX_TAB_KIND.to_string(),
            title: "Codex Chat".to_string(),
            created_at: now,
            updated_at: now,
            payload: serde_json::json!({
                "codexThreadId": "thread-stale",
                "codexThreadOwnedByAlera": true,
            }),
        })
        .await
        .unwrap();
    let (inbox, mut inbox_receiver) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;

    actor
        .handle_line(
            1,
            serde_json::json!({
                "id": 1,
                "type": "tab.remove",
                "payload": {"id": "stale-codex-tab"},
            })
            .to_string(),
        )
        .await;
    let completion = inbox_receiver.recv().await.unwrap();
    actor.handle(completion).await;
    let response = loop {
        let response = receiver.recv().await.unwrap().as_json().unwrap();
        if response["id"] == 1 {
            break response;
        }
    };

    assert_eq!(response["ok"], true);
    assert!(actor
        .runtime_store
        .find_workspace_tab("stale-codex-tab")
        .await
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn shutdown_response_precedes_disposal_marker() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut receiver) = crate::terminal_host::client::ClientHandle::test_channels();
    let mut actor = crate::terminal_host::server::actor_test_harness::test_actor(
        &dir,
        std::collections::HashMap::from([(
            1,
            crate::terminal_host::server::actor_test_harness::local_client(handle),
        )]),
        std::collections::HashMap::new(),
    )
    .await;
    let (inbox, mut inbox_receiver) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;

    actor
        .handle_line(
            1,
            serde_json::json!({
                "id": 1,
                "type": "host.shutdown",
                "payload": {},
            })
            .to_string(),
        )
        .await;

    let response = receiver.recv().await.unwrap().as_json().unwrap();
    assert_eq!(response["id"], 1);
    assert_eq!(response["ok"], true);
    let marker = receiver.recv().await.unwrap();
    assert!(matches!(
        marker,
        crate::terminal_host::client::ClientFrame::OrderedControl { frame, .. }
            if matches!(
                *frame,
                crate::terminal_host::client::ClientFrame::ShutdownRuntimeAfterWrite { .. }
            )
    ));
    assert!(inbox_receiver.try_recv().is_err());
}

#[tokio::test]
async fn authenticated_mobile_client_can_request_a_safe_runtime_restart() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, mut receiver) = crate::terminal_host::client::ClientHandle::test_channels();
    let mut actor = crate::terminal_host::server::actor_test_harness::test_actor(
        &dir,
        std::collections::HashMap::from([(
            1,
            crate::terminal_host::server::actor_test_harness::mobile_client(handle, "phone"),
        )]),
        std::collections::HashMap::new(),
    )
    .await;
    let (inbox, mut inbox_receiver) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;

    actor
        .handle_line(
            1,
            serde_json::json!({
                "id": 1,
                "type": "host.restart",
                "payload": {"force": false},
            })
            .to_string(),
        )
        .await;

    let response = receiver.recv().await.unwrap().as_json().unwrap();
    assert_eq!(response["id"], 1);
    assert_eq!(response["ok"], true);
    assert_eq!(response["payload"]["restarting"], true);
    let marker = receiver.recv().await.unwrap();
    assert!(matches!(
        marker,
        crate::terminal_host::client::ClientFrame::OrderedControl { frame, .. }
            if matches!(
                *frame,
                crate::terminal_host::client::ClientFrame::RestartRuntimeAfterWrite { .. }
            )
    ));
    assert!(inbox_receiver.try_recv().is_err());
}

#[test]
fn mobile_allowlist_includes_workspace_mutations() {
    assert!(mobile_request_allowed("workspace.setPinned"));
    assert!(mobile_request_allowed("workspace.createManaged"));
    assert!(mobile_request_allowed("workspace.storageImpact"));
    assert!(mobile_request_allowed("workspace.removeManaged"));
    assert!(mobile_request_allowed("workspaceRelation.link"));
    assert!(mobile_request_allowed("workspaceRelation.unlink"));
    assert!(mobile_request_allowed("tab.remove"));
    assert!(mobile_request_allowed("tab.rename"));
    assert!(mobile_request_allowed("mobile.runtimeSettings.get"));
    assert!(mobile_request_allowed("mobile.runtimeSettings.update"));
    assert!(mobile_request_allowed("agentQuota.snapshot"));
    assert!(mobile_request_allowed("agentUsage.snapshot"));
    assert!(mobile_request_allowed("agentQuota.fetchClaudeTui"));
    assert!(mobile_request_allowed("agentQuota.consumeCodexResetCredit"));
    assert!(mobile_request_allowed("cliRegistration.status"));
    assert!(mobile_request_allowed("cliRegistration.install"));
    assert!(mobile_request_allowed("agentSkill.install"));
    assert!(mobile_request_allowed("terminal.restart"));
    assert!(mobile_request_allowed("host.restart"));
    assert!(mobile_request_allowed("mobile.cloudEnrollment.create"));
    assert!(mobile_request_allowed("mobile.cloudSubscriptions.refresh"));
    assert!(mobile_request_allowed("agentProfile.list"));
    assert!(mobile_request_allowed("agentProfile.launch"));
    assert!(mobile_request_allowed("aiText.workspaceIdentity.generate"));
    assert!(mobile_request_allowed("aiText.cancel"));
    assert!(mobile_request_allowed("mobile.promptImage.start"));
    assert!(mobile_request_allowed("mobile.promptImage.chunk"));
    assert!(mobile_request_allowed("mobile.promptImage.complete"));
    assert!(mobile_request_allowed("mobile.promptImage.cancel"));
    for request in [
        "codex.tab.create",
        "codex.thread.open",
        "codex.thread.list",
        "codex.thread.resume",
        "codex.thread.history",
        "codex.thread.new",
        "codex.thread.clear",
        "codex.thread.snapshot",
        "codex.thread.items.list",
        "codex.goal.get",
        "codex.goal.set",
        "codex.goal.clear",
        "codex.model.list",
        "codex.collaborationModes.list",
        "codex.skills.list",
        "codex.apps.list",
        "codex.turn.start",
        "codex.turn.interrupt",
        "codex.turn.steer",
        "codex.thread.rename",
        "codex.thread.compact",
        "codex.review.branches",
        "codex.review.start",
        "codex.response",
    ] {
        assert!(
            mobile_request_allowed(request),
            "{request} should be allowed"
        );
    }
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
    assert!(!mobile_request_allowed("mobile.device.revoke"));
    assert!(!mobile_request_allowed("mobile.device.delete"));
    assert!(!mobile_request_allowed("mobile.device.rename"));
    assert!(!mobile_request_allowed("runtimeMetadata.set"));
    assert!(!mobile_request_allowed("browser.capabilities"));
    assert!(!mobile_request_allowed("browser.tabs.open"));
    assert!(!mobile_request_allowed("browser.driver.register"));
    assert!(!mobile_request_allowed("account.status"));
    assert!(!mobile_request_allowed("account.signIn.start"));
    assert!(!mobile_request_allowed("account.signOut"));
    assert!(!mobile_request_allowed("terminal.pulse.status"));
    assert!(!mobile_request_allowed("terminal.pulse.configure"));
}

#[test]
fn mobile_allowlist_excludes_emulator_verbs() {
    for request in [
        "emulator.capabilities",
        "emulator.list",
        "emulator.attach",
        "emulator.detach",
        "emulator.tap",
        "emulator.gesture",
        "emulator.type",
        "emulator.key",
        "emulator.button",
        "emulator.rotate",
        "emulator.shutdown",
    ] {
        assert!(
            !mobile_request_allowed(request),
            "{request} must stay desktop-only"
        );
    }
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
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_TERMINAL_RESTART_CAPABILITY));
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_RESTART_CAPABILITY));
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_MOBILE_CLOUD_ENROLLMENT_CAPABILITY));
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_MOBILE_PROMPT_IMAGE_UPLOAD_CAPABILITY));
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_CODEX_CHAT_CAPABILITY));
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_CODEX_GOALS_CAPABILITY));
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_CODEX_TURN_POLICY_CAPABILITY));
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_AI_DICTATION_MODELS_CAPABILITY));
}

#[test]
fn mobile_hello_accepts_an_additive_cloud_device_id() {
    let hello: MobileHelloRequest = serde_json::from_value(serde_json::json!({
        "protocolVersion": MOBILE_PROTOCOL_VERSION,
        "deviceId": "pairing-device",
        "deviceToken": "pairing-token",
        "cloudDeviceId": "installation-device",
    }))
    .unwrap();
    assert_eq!(
        hello.cloud_device_id.as_deref(),
        Some("installation-device")
    );

    let legacy: MobileHelloRequest = serde_json::from_value(serde_json::json!({
        "protocolVersion": MOBILE_PROTOCOL_VERSION,
        "deviceId": "pairing-device",
        "deviceToken": "pairing-token",
    }))
    .unwrap();
    assert_eq!(legacy.cloud_device_id, None);
}

#[test]
fn account_and_push_capabilities_are_additive_and_not_mobile_admin_verbs() {
    assert_eq!(PROTOCOL_VERSION, 4);
    assert_eq!(RUNTIME_HOST_ACCOUNT_CAPABILITY, "aleraAccountV1");
    assert_eq!(
        RUNTIME_HOST_CLOUD_PUSH_CAPABILITY,
        "cloudPushNotificationsV1"
    );
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_MOBILE_CLOUD_ENROLLMENT_CAPABILITY));
    assert!(!MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_ACCOUNT_CAPABILITY));
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_CODEX_RESET_CREDITS_CAPABILITY));
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_AI_TEXT_WORKSPACE_IDENTITY_CAPABILITY));
    assert!(MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_AI_TEXT_SPEECH_MESSAGE_CAPABILITY));
    assert!(
        MOBILE_HELLO_CAPABILITIES.contains(&RUNTIME_HOST_AGENT_PROFILE_PROMPT_LAUNCH_CAPABILITY)
    );
}

#[test]
fn soft_shutdown_busy_message_includes_agents() {
    assert_eq!(host_shutdown_busy_message(0, 0, 0, false), None);
    assert_eq!(
        host_shutdown_busy_message(2, 1, 0, false).as_deref(),
        Some(
            "Runtime host has 2 active agent(s), 1 active terminal session(s), 0 active background job(s), and 0 active push subscription(s). Retry with --force to stop it."
        )
    );
    assert_eq!(
        host_shutdown_busy_message(1, 0, 0, false).as_deref(),
        Some(
            "Runtime host has 1 active agent(s), 0 active terminal session(s), 0 active background job(s), and 0 active push subscription(s). Retry with --force to stop it."
        )
    );
    assert!(host_shutdown_busy_message(0, 0, 0, true)
        .unwrap()
        .contains("1 active push subscription"));
}
