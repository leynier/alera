use std::collections::{BTreeSet, HashMap};
use std::sync::Arc;

use alera_core::runtime::WorkspaceTabRecord;
use chrono::Utc;
use serde_json::{json, Value};
use tokio::sync::mpsc::UnboundedReceiver;
use tokio::sync::Mutex;

use crate::terminal_host::client::{ClientFrame, ClientHandle};
use crate::terminal_host::emulator::EmulatorManager;
use crate::terminal_host::protocol::MOBILE_EMULATOR_TAB_KIND;

use super::actor_test_harness::{local_client, test_actor};
use super::browser_broker::{BrowserCall, BrowserDriver, BrowserPage};
use super::emulator_request_queue::ActivePointerState;
use super::{ServerActor, ServerCommand};

fn emulator_tab(tab_id: &str, workspace_id: &str) -> WorkspaceTabRecord {
    let now = Utc::now();
    WorkspaceTabRecord {
        id: tab_id.to_string(),
        workspace_id: workspace_id.to_string(),
        kind: MOBILE_EMULATOR_TAB_KIND.to_string(),
        title: "Test Device".to_string(),
        created_at: now,
        updated_at: now,
        payload: json!({
            "platform": "android",
            "deviceId": "android:test-device",
        }),
    }
}

async fn actor_with_tab(
    dir: &tempfile::TempDir,
    tab: &WorkspaceTabRecord,
) -> (ServerActor, UnboundedReceiver<ClientFrame>) {
    let (handle, receiver) = ClientHandle::test_channels();
    let mut client = local_client(handle);
    client.supports_mobile_emulator_tab_kind = true;
    let actor = test_actor(dir, HashMap::from([(1, client)]), HashMap::new()).await;
    actor
        .runtime_store
        .upsert_workspace_tab(tab.clone())
        .await
        .unwrap();
    (actor, receiver)
}

async fn tab_exists(actor: &ServerActor, tab_id: &str) -> bool {
    actor
        .runtime_store
        .find_workspace_tab(tab_id)
        .await
        .unwrap()
        .is_some()
}

async fn receive_command(receiver: &mut UnboundedReceiver<ServerCommand>) -> ServerCommand {
    tokio::time::timeout(std::time::Duration::from_secs(1), receiver.recv())
        .await
        .expect("the queued operation should complete")
        .unwrap()
}

async fn actor_with_failing_owned_emulator(
    dir: &tempfile::TempDir,
    tab: &WorkspaceTabRecord,
) -> (
    ServerActor,
    UnboundedReceiver<ClientFrame>,
    UnboundedReceiver<ServerCommand>,
) {
    let (mut actor, receiver) = actor_with_tab(dir, tab).await;
    let manager = Arc::new(Mutex::new(EmulatorManager::new(dir.path()).await.unwrap()));
    manager
        .lock()
        .await
        .insert_owned_android_session_for_shutdown_failure_test(
            &tab.workspace_id,
            &tab.id,
            dir.path().join("missing-adb"),
        );
    actor.emulators = Some(manager);
    let (inbox, inbox_receiver) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;
    (actor, receiver, inbox_receiver)
}

async fn request(
    actor: &mut ServerActor,
    receiver: &mut UnboundedReceiver<ClientFrame>,
    inbox_receiver: &mut UnboundedReceiver<ServerCommand>,
    request_type: &str,
    payload: Value,
) -> Value {
    actor
        .handle_line(
            1,
            json!({
                "id": 1,
                "type": request_type,
                "payload": payload,
            })
            .to_string(),
        )
        .await;
    loop {
        tokio::select! {
            command = inbox_receiver.recv() => {
                actor.handle(command.expect("the completion should be delivered")).await;
            }
            frame = receiver.recv() => {
                let response = frame
                    .expect("the response should be delivered")
                    .as_json()
                    .expect("the response should be JSON");
                if response["id"] == 1 {
                    return response;
                }
            }
        }
    }
}

#[tokio::test]
async fn tab_removal_still_deletes_the_record_after_emulator_preflight_succeeds() {
    let dir = tempfile::tempdir().unwrap();
    let tab = emulator_tab("emulator-tab", "workspace");
    let (mut actor, mut receiver) = actor_with_tab(&dir, &tab).await;
    actor.emulators = Some(Arc::new(Mutex::new(
        EmulatorManager::new(dir.path()).await.unwrap(),
    )));
    let (inbox, mut inbox_receiver) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;

    let response = request(
        &mut actor,
        &mut receiver,
        &mut inbox_receiver,
        "tab.remove",
        json!({"id": tab.id}),
    )
    .await;

    assert_eq!(response["ok"], true);
    assert!(!tab_exists(&actor, "emulator-tab").await);
}

#[tokio::test]
async fn successful_tab_removal_drains_pending_browser_calls() {
    let dir = tempfile::tempdir().unwrap();
    let mut tab = emulator_tab("browser-tab", "workspace");
    tab.kind = "browser".to_string();
    tab.payload = json!({"browserProfileId": "default"});
    let (mut actor, mut remover_rx) = actor_with_tab(&dir, &tab).await;
    let (browser_handle, mut browser_rx) = ClientHandle::test_channels();
    actor.clients.insert(2, local_client(browser_handle));
    actor.browser.register_driver(BrowserDriver {
        owner_client_id: 2,
        app_instance_id: "app".to_string(),
        driver_instance_id: "driver".to_string(),
        engine: "test".to_string(),
        platform: "test".to_string(),
        capabilities: BTreeSet::new(),
    });
    let (page, _) = actor
        .browser
        .sync_page(
            2,
            BrowserPage {
                tab_id: tab.id.clone(),
                workspace_id: tab.workspace_id.clone(),
                profile_id: "default".to_string(),
                generation: 0,
                document_generation: 1,
                url: Some("https://example.com".to_string()),
                title: Some("Example".to_string()),
                capabilities: BTreeSet::new(),
                owner_client_id: 2,
            },
        )
        .unwrap();
    actor
        .browser
        .enqueue(BrowserCall {
            correlation_id: "pending-call".to_string(),
            requester_client_id: 2,
            requester_request_id: 91,
            owner_client_id: 2,
            request_type: "browser.snapshot".to_string(),
            tab_id: tab.id.clone(),
            generation: page.generation,
            params: json!({"pageId": tab.id}),
            deadline_at_ms: i64::MAX,
        })
        .unwrap();
    let (inbox, mut inbox_rx) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;

    let response = request(
        &mut actor,
        &mut remover_rx,
        &mut inbox_rx,
        "tab.remove",
        json!({"id": "browser-tab"}),
    )
    .await;

    assert_eq!(response["ok"], true);
    assert!(actor.browser.page("browser-tab").is_none());
    assert_eq!(actor.browser.active_jobs(), 0);
    let cancel = browser_rx.recv().await.unwrap().as_json().unwrap();
    assert_eq!(cancel["event"], "browserDriverCancel");
    assert_eq!(cancel["payload"]["correlationId"], "pending-call");
    let failure = browser_rx.recv().await.unwrap().as_json().unwrap();
    assert_eq!(failure["id"], 91);
    assert_eq!(failure["payload"]["error"]["code"], "page_closed");
}

#[tokio::test]
async fn tab_removal_does_not_block_the_actor_while_the_emulator_manager_is_busy() {
    let dir = tempfile::tempdir().unwrap();
    let tab = emulator_tab("emulator-tab", "workspace");
    let (mut actor, mut receiver) = actor_with_tab(&dir, &tab).await;
    let manager = Arc::new(Mutex::new(EmulatorManager::new(dir.path()).await.unwrap()));
    actor.emulators = Some(manager.clone());
    let (inbox, mut inbox_receiver) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;
    let manager_guard = manager.lock().await;

    actor
        .handle_line(
            1,
            json!({
                "id": 1,
                "type": "tab.remove",
                "payload": {"id": tab.id.clone()},
            })
            .to_string(),
        )
        .await;
    actor
        .handle_line(
            1,
            json!({
                "id": 2,
                "type": "tab.find",
                "payload": {"id": tab.id},
            })
            .to_string(),
        )
        .await;

    let response = tokio::time::timeout(std::time::Duration::from_secs(1), receiver.recv())
        .await
        .expect("the actor should answer while the manager remains locked")
        .unwrap()
        .as_json()
        .unwrap();
    assert_eq!(response["id"], 2);
    assert_eq!(response["ok"], true);
    assert_eq!(response["payload"]["id"], "emulator-tab");
    actor
        .handle_line(
            1,
            json!({
                "id": 4,
                "type": "tab.upsert",
                "payload": tab.clone(),
            })
            .to_string(),
        )
        .await;
    let response = receiver.recv().await.unwrap().as_json().unwrap();
    assert_eq!(response["id"], 4);
    assert_eq!(response["ok"], false);
    assert!(response["error"]
        .as_str()
        .unwrap()
        .contains("runtime mutation is in progress"));
    assert!(inbox_receiver.try_recv().is_err());
    actor
        .handle_line(
            1,
            json!({
                "id": 3,
                "type": "emulator.acquire",
                "payload": {"tabId": "emulator-tab"},
            })
            .to_string(),
        )
        .await;
    assert_eq!(actor.emulator_requests.outstanding(), 2);
    assert!(tab_exists(&actor, "emulator-tab").await);

    drop(manager_guard);
    let command = receive_command(&mut inbox_receiver).await;
    assert!(matches!(
        &command,
        ServerCommand::RuntimeMutationFinished(finished) if finished.request_id == 1
    ));
    actor.handle(command).await;
    loop {
        let response = receiver.recv().await.unwrap().as_json().unwrap();
        if response["id"] == 1 {
            assert_eq!(response["ok"], true);
            break;
        }
    }
    let command = receive_command(&mut inbox_receiver).await;
    assert!(matches!(
        command,
        ServerCommand::EmulatorRequestFinished { request_id: 3, .. }
    ));
    actor.handle(command).await;
    loop {
        let response = receiver.recv().await.unwrap().as_json().unwrap();
        if response["id"] == 3 {
            assert_eq!(response["payload"]["error"]["code"], "tab_not_found");
            break;
        }
    }
    assert!(!tab_exists(&actor, "emulator-tab").await);
}

#[tokio::test]
async fn tab_removal_bypasses_its_active_pointer_and_cleans_only_affected_owners() {
    let dir = tempfile::tempdir().unwrap();
    let first_tab = emulator_tab("first-tab", "workspace");
    let second_tab = emulator_tab("second-tab", "workspace");
    let (handle, _receiver) = ClientHandle::test_channels();
    let mut actor = test_actor(
        &dir,
        HashMap::from([(1, local_client(handle))]),
        HashMap::new(),
    )
    .await;
    actor
        .runtime_store
        .upsert_workspace_tab(first_tab)
        .await
        .unwrap();
    actor
        .runtime_store
        .upsert_workspace_tab(second_tab)
        .await
        .unwrap();
    actor.emulators = Some(Arc::new(Mutex::new(
        EmulatorManager::new(dir.path()).await.unwrap(),
    )));
    actor.emulator_requests.active_pointers.insert(
        "first-tab".into(),
        ActivePointerState {
            client_id: 1,
            generation: 1,
        },
    );
    actor.emulator_requests.active_pointers.insert(
        "second-tab".into(),
        ActivePointerState {
            client_id: 1,
            generation: 2,
        },
    );
    let (inbox, mut inbox_receiver) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = inbox;

    for (request_id, request_type, payload) in [
        (1, "tab.remove", json!({"id": "first-tab"})),
        (2, "tab.remove", json!({"id": "second-tab"})),
        (3, "emulator.list", json!({})),
    ] {
        actor
            .handle_line(
                1,
                json!({
                    "id": request_id,
                    "type": request_type,
                    "payload": payload,
                })
                .to_string(),
            )
            .await;
    }

    let first = receive_command(&mut inbox_receiver).await;
    assert!(matches!(
        &first,
        ServerCommand::RuntimeMutationFinished(finished) if finished.request_id == 1
    ));
    actor.handle(first).await;
    assert!(!actor
        .emulator_requests
        .active_pointers
        .contains_key("first-tab"));
    assert!(actor
        .emulator_requests
        .active_pointers
        .contains_key("second-tab"));

    let second = receive_command(&mut inbox_receiver).await;
    assert!(matches!(
        &second,
        ServerCommand::RuntimeMutationFinished(finished) if finished.request_id == 2
    ));
    actor.handle(second).await;
    assert!(actor.emulator_requests.active_pointers.is_empty());

    let next = receive_command(&mut inbox_receiver).await;
    assert!(matches!(
        next,
        ServerCommand::EmulatorRequestFinished { request_id: 3, .. }
    ));
}

#[tokio::test]
async fn tab_removal_preserves_the_record_when_owned_device_shutdown_fails() {
    let dir = tempfile::tempdir().unwrap();
    let tab = emulator_tab("emulator-tab", "workspace");
    let (mut actor, mut receiver, mut inbox_receiver) =
        actor_with_failing_owned_emulator(&dir, &tab).await;
    actor.emulator_requests.active_pointers.insert(
        tab.id.clone(),
        ActivePointerState {
            client_id: 1,
            generation: 1,
        },
    );
    for (request_id, request_type, payload) in [
        (1, "tab.remove", json!({"id": tab.id})),
        (2, "emulator.list", json!({})),
    ] {
        actor
            .handle_line(
                1,
                json!({
                    "id": request_id,
                    "type": request_type,
                    "payload": payload,
                })
                .to_string(),
            )
            .await;
    }
    let completion = receive_command(&mut inbox_receiver).await;
    actor.handle(completion).await;
    let response = receiver.recv().await.unwrap().as_json().unwrap();

    assert_eq!(response["ok"], false);
    assert!(response["error"]
        .as_str()
        .unwrap()
        .contains("Could not close mobile emulator tab"));
    assert!(tab_exists(&actor, "emulator-tab").await);
    assert!(actor
        .emulators
        .as_ref()
        .unwrap()
        .lock()
        .await
        .contains("emulator-tab"));
    assert!(actor.emulator_requests.active_pointers.is_empty());
    let next = receive_command(&mut inbox_receiver).await;
    assert!(matches!(
        next,
        ServerCommand::EmulatorRequestFinished { request_id: 2, .. }
    ));
}

#[tokio::test]
async fn workspace_sleep_preserves_tabs_when_owned_device_shutdown_fails() {
    let dir = tempfile::tempdir().unwrap();
    let tab = emulator_tab("emulator-tab", "workspace");
    let (mut actor, mut receiver, mut inbox_receiver) =
        actor_with_failing_owned_emulator(&dir, &tab).await;

    let response = request(
        &mut actor,
        &mut receiver,
        &mut inbox_receiver,
        "workspace.sleep",
        json!({"workspaceId": "workspace"}),
    )
    .await;

    assert_eq!(response["ok"], false);
    assert!(response["error"]
        .as_str()
        .unwrap()
        .contains("Could not close mobile emulators for workspace"));
    assert!(tab_exists(&actor, "emulator-tab").await);
}
