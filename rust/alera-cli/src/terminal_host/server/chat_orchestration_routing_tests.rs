use std::collections::HashMap;
use std::sync::Arc;

use serde_json::{json, Value};
use tokio::sync::mpsc::UnboundedReceiver;

use super::super::actor_test_harness::test_actor;
use super::super::agent_chat_runtime::events::NullSink;
use super::super::agent_chat_runtime::{
    AgentChatRuntime, InstanceDirectory, ProductionProviderFactory,
};
use super::super::chat_orchestration::{
    BoundChat, ChatCredentialLaunchHook, ChatOrchestrationService, RuntimeTargetResolver,
};
use super::super::{ClientFrame, ClientHandle, ClientState, ServerActor};

const HUB: u64 = 1;
const CLI: u64 = 2;

async fn fixture(
    satellite: bool,
) -> (
    tempfile::TempDir,
    ServerActor,
    UnboundedReceiver<ClientFrame>,
    UnboundedReceiver<ClientFrame>,
) {
    let root = tempfile::tempdir().unwrap();
    let (hub, hub_frames) = ClientHandle::test_channels();
    let (cli, cli_frames) = ClientHandle::test_channels();
    let clients = HashMap::from([
        (HUB, ClientState::local(hub, false)),
        (CLI, ClientState::local(cli, false)),
    ]);
    let mut actor = test_actor(&root, clients, HashMap::new()).await;
    if satellite {
        actor
            .runtime_store
            .set_metadata(crate::hub_federation::SATELLITE_METADATA_KEY, "1")
            .await
            .unwrap();
        actor
            .try_handle_hub_reverse_request(HUB, 1, "hub.link.register", &json!({}))
            .unwrap();
    }
    (root, actor, hub_frames, cli_frames)
}

fn bind(actor: &mut ServerActor) {
    actor
        .clients
        .get_mut(&CLI)
        .unwrap()
        .chat_orchestration_binding = Some(BoundChat {
        chat_id: "satellite-chat".into(),
        generation: 7,
        runtime_mode: "auto".into(),
        credential_hash: "a".repeat(64),
        origin_host_id: None,
    });
}

#[tokio::test]
async fn bound_satellite_disallows_mutations_before_any_reverse_forwarding() {
    let (_root, mut actor, mut hub_frames, mut cli_frames) = fixture(true).await;
    bind(&mut actor);
    for (id, verb) in [
        (11, "project.upsert"),
        (12, "project.remove"),
        (13, "workspace.createShared"),
        (14, "orchestration.delegate"),
        (15, "hub.forward"),
    ] {
        actor.handle_line(CLI, json!({"id":id,"type":verb,"payload":{"type":"project.upsert","payload":{},"scope":"desktop","actor":"desktop"}}).to_string()).await;
        let answer = cli_frames.try_recv().unwrap().as_json().unwrap();
        assert_eq!(answer["id"], id);
        assert_eq!(answer["errorCode"], "chat_scope_denied", "{verb}: {answer}");
        assert!(hub_frames.try_recv().is_err(), "{verb} reached the hub");
    }
    let direct = actor
        .try_forward_to_hub(CLI, 16, "project.upsert", &json!({}))
        .await
        .unwrap_err();
    assert_eq!(direct.wire_response(0)["errorCode"], "chat_scope_denied");
    assert!(hub_frames.try_recv().is_err());
}

#[tokio::test]
async fn bound_satellite_forwards_before_local_service_and_stamps_actual_authority() {
    let (_root, mut actor, mut hub_frames, mut cli_frames) = fixture(true).await;
    bind(&mut actor);
    assert!(actor.chat_orchestration.is_none());
    actor.handle_line(CLI, json!({"id":20,"type":"chatOrchestration.list","payload":{"actor":"desktop","scope":"desktop","originChatId":"spoofed-chat","chatAuthority":{"originChatId":"spoofed-chat","generation":99,"credentialHash":"b".repeat(64)}}}).to_string()).await;
    assert!(
        cli_frames.try_recv().is_err(),
        "the satellite answered against its own ledger"
    );
    let asked = hub_frames.try_recv().unwrap().as_json().unwrap();
    assert_eq!(asked["event"], "hub.request");
    assert_eq!(asked["payload"]["type"], "chatOrchestration.list");
    assert_eq!(
        asked["payload"]["chatAuthority"]["originChatId"],
        "satellite-chat"
    );
    assert_eq!(asked["payload"]["chatAuthority"]["generation"], 7);
    assert_eq!(
        asked["payload"]["chatAuthority"]["credentialHash"],
        "a".repeat(64)
    );
}

#[tokio::test]
async fn local_helper_also_forwards_satellite_bound_calls_without_local_ledger() {
    let (_root, mut actor, mut hub_frames, mut cli_frames) = fixture(true).await;
    bind(&mut actor);
    assert!(actor
        .try_start_local_chat_orchestration_request(
            CLI,
            21,
            "chatOrchestration.task",
            &json!({"taskId":"hub-task"})
        )
        .await
        .unwrap());
    assert!(cli_frames.try_recv().is_err());
    let asked = hub_frames.try_recv().unwrap().as_json().unwrap();
    assert_eq!(asked["payload"]["type"], "chatOrchestration.task");
    assert_eq!(
        asked["payload"]["chatAuthority"]["originChatId"],
        "satellite-chat"
    );
}

#[tokio::test]
async fn satellite_human_forwards_without_borrowing_payload_agent_authority() {
    let (_root, mut actor, mut hub_frames, mut cli_frames) = fixture(true).await;
    actor.handle_line(CLI, json!({"id":22,"type":"chatOrchestration.list","payload":{"originChatId":"spoofed-chat","chatAuthority":{"originChatId":"spoofed-chat"}}}).to_string()).await;
    let asked = hub_frames.try_recv().unwrap().as_json().unwrap();
    assert_eq!(asked["payload"]["type"], "chatOrchestration.list");
    assert!(asked["payload"].get("chatAuthority").is_none());
    assert!(cli_frames.try_recv().is_err());
}

#[tokio::test]
async fn an_unlinked_satellite_cannot_fall_back_to_its_own_ledger() {
    let (_root, mut actor, mut hub_frames, mut cli_frames) = fixture(true).await;
    bind(&mut actor);
    actor.forget_hub_reverse_client(HUB);
    actor
        .handle_line(
            CLI,
            json!({"id":23,"type":"chatOrchestration.list","payload":{}}).to_string(),
        )
        .await;
    let answer = cli_frames.try_recv().unwrap().as_json().unwrap();
    assert_eq!(answer["ok"], false);
    assert!(answer["error"]
        .as_str()
        .unwrap()
        .contains("No Alera desktop is linked"));
    assert!(hub_frames.try_recv().is_err());
}

fn install_local_service(actor: &mut ServerActor, root: &tempfile::TempDir) {
    let store = actor.runtime_store.clone();
    let runtime = AgentChatRuntime::new(
        store.clone(),
        Arc::new(ProductionProviderFactory),
        Arc::new(store.clone()),
        Box::new(NullSink),
        Arc::new(InstanceDirectory::default()),
    );
    let credentials = ChatCredentialLaunchHook::new(store.clone(), root.path().into()).unwrap();
    actor.chat_orchestration = Some(ChatOrchestrationService::new(
        store.clone(),
        runtime,
        Arc::new(RuntimeTargetResolver::new(store)),
        credentials,
    ));
}

#[tokio::test]
async fn standalone_humans_and_hub_link_requests_keep_local_dispatch() {
    for satellite in [false, true] {
        let (root, mut actor, mut hub_frames, mut cli_frames) = fixture(satellite).await;
        install_local_service(&mut actor, &root);
        let (inbox, mut commands) = super::super::ServerInbox::channel();
        actor.inbox = inbox;
        let asker = if satellite { HUB } else { CLI };
        actor
            .handle_line(
                asker,
                json!({"id":24,"type":"chatOrchestration.list","payload":{}}).to_string(),
            )
            .await;
        let finished = tokio::time::timeout(std::time::Duration::from_secs(5), commands.recv())
            .await
            .unwrap()
            .unwrap();
        actor.handle(finished).await;
        let frame = if satellite {
            hub_frames.try_recv().unwrap()
        } else {
            cli_frames.try_recv().unwrap()
        };
        let answer = frame.as_json().unwrap();
        assert_eq!(answer["id"], 24);
        assert_eq!(answer["ok"], true);
        assert_eq!(answer["payload"]["chats"], json!([]));
        assert!(hub_frames.try_recv().is_err());
        assert!(cli_frames.try_recv().is_err());
    }
}

#[tokio::test]
async fn preflight_preserves_initial_hello_but_bound_connections_cannot_unbind_by_rehello() {
    let (_root, mut actor, mut hub_frames, mut cli_frames) = fixture(false).await;
    actor.clients.get_mut(&CLI).unwrap().authenticated = false;
    let hello: Value = json!({"id":25,"type":"hello","payload":{"token":"token","protocolVersion":crate::terminal_host::protocol::PROTOCOL_VERSION}});
    actor.handle_line(CLI, hello.to_string()).await;
    assert_eq!(
        cli_frames.try_recv().unwrap().as_json().unwrap()["ok"],
        true
    );
    bind(&mut actor);
    actor.handle_line(CLI, hello.to_string()).await;
    let denied = cli_frames.try_recv().unwrap().as_json().unwrap();
    assert_eq!(denied["errorCode"], "chat_scope_denied");
    assert_eq!(
        actor.chat_orchestration_binding(CLI).unwrap().chat_id,
        "satellite-chat"
    );
    assert!(hub_frames.try_recv().is_err());
}

#[tokio::test]
async fn idless_hello_notification_cannot_reset_a_bound_connections_identity() {
    let (_root, mut actor, mut hub_frames, mut cli_frames) = fixture(false).await;
    bind(&mut actor);
    let payload = json!({"token":"token", "protocolVersion":crate::terminal_host::protocol::PROTOCOL_VERSION});
    let denied = actor.handle_hello_request(CLI, &payload).await.unwrap_err();
    assert_eq!(denied.wire_response(0)["errorCode"], "chat_scope_denied");
    assert_eq!(
        actor.chat_orchestration_binding(CLI).unwrap().chat_id,
        "satellite-chat"
    );
    let synchronous = actor.handle_hello(CLI, &payload).unwrap_err();
    assert_eq!(
        synchronous.wire_response(0)["errorCode"],
        "chat_scope_denied"
    );
    actor
        .handle_line(CLI, json!({"type":"hello", "payload":payload}).to_string())
        .await;
    assert!(
        !actor.clients.contains_key(&CLI),
        "a rejected notification must disconnect instead of becoming human"
    );
    assert!(cli_frames.try_recv().is_err());
    assert!(hub_frames.try_recv().is_err());
}
