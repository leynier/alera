use std::collections::HashMap;

use super::super::actor_test_harness::test_actor;
use super::super::{ClientHandle, ClientKind, ClientState};
use super::*;

const HUB: u64 = 1;
const CLI: u64 = 2;
const PHONE: u64 = 3;

async fn satellite() -> (
    tempfile::TempDir,
    ServerActor,
    tokio::sync::mpsc::UnboundedReceiver<super::super::ClientFrame>,
    tokio::sync::mpsc::UnboundedReceiver<super::super::ClientFrame>,
) {
    let root = tempfile::tempdir().unwrap();
    let mut clients = HashMap::new();
    let (hub, hub_frames) = ClientHandle::test_channels();
    clients.insert(HUB, ClientState::local(hub, false));
    let (cli, cli_frames) = ClientHandle::test_channels();
    clients.insert(CLI, ClientState::local(cli, false));
    let (phone, _) = ClientHandle::test_channels();
    let mut mobile = ClientState::local(phone, false);
    mobile.kind = ClientKind::Mobile;
    clients.insert(PHONE, mobile);
    let actor = test_actor(&root, clients, HashMap::new()).await;
    (root, actor, hub_frames, cli_frames)
}

async fn mark_as_satellite(actor: &ServerActor) {
    actor
        .runtime_store
        .set_metadata(crate::hub_federation::SATELLITE_METADATA_KEY, "1")
        .await
        .unwrap();
}

fn handled(outcome: HostResult<Option<ReverseOutcome>>) -> Value {
    match outcome.unwrap().expect("a reverse channel verb") {
        ReverseOutcome::Answer(value) => value,
        ReverseOutcome::Deferred => json!("deferred"),
    }
}

fn register_hub(actor: &mut ServerActor) {
    handled(actor.try_handle_hub_reverse_request(HUB, 1, "hub.link.register", &json!({})));
}

#[tokio::test]
async fn a_forwarded_question_travels_to_the_hub_and_its_answer_comes_back() {
    let (_root, mut actor, mut hub_frames, mut cli_frames) = satellite().await;
    let unlinked = actor
        .try_handle_hub_reverse_request(CLI, 7, "hub.forward", &json!({"type": "project.list"}))
        .unwrap_err();
    assert!(
        unlinked.to_string().contains("No Alera desktop is linked"),
        "{unlinked}"
    );

    register_hub(&mut actor);
    let status =
        handled(actor.try_handle_hub_reverse_request(CLI, 2, "hub.link.status", &json!({})));
    assert_eq!(status["linked"], true);

    let outcome = handled(actor.try_handle_hub_reverse_request(
        CLI,
        7,
        "hub.forward",
        &json!({"type": "workspace.list", "payload": {"hostId": "origin"}}),
    ));
    assert_eq!(
        outcome, "deferred",
        "the CLI is answered when the hub replies"
    );
    let asked = hub_frames.try_recv().unwrap().as_json().unwrap();
    assert_eq!(asked["event"], HUB_REQUEST_EVENT, "{asked}");
    assert_eq!(asked["payload"]["type"], "workspace.list");
    assert_eq!(asked["payload"]["payload"]["hostId"], "origin");
    let reverse_id = asked["payload"]["requestId"].as_str().unwrap().to_string();

    let stranger = actor
        .try_handle_hub_reverse_request(
            CLI,
            8,
            "hub.respond",
            &json!({"requestId": reverse_id, "ok": true, "payload": {"items": []}}),
        )
        .unwrap_err();
    assert!(
        stranger.to_string().contains("Only a hub link"),
        "{stranger}"
    );

    handled(actor.try_handle_hub_reverse_request(
        HUB,
        3,
        "hub.respond",
        &json!({"requestId": reverse_id, "ok": true, "payload": {"items": [{"id": "w1"}]}}),
    ));
    let answer = cli_frames.try_recv().unwrap().as_json().unwrap();
    assert_eq!(answer["id"], 7, "{answer}");
    assert_eq!(answer["ok"], true, "{answer}");
    assert_eq!(answer["payload"]["items"][0]["id"], "w1");
}

#[tokio::test]
async fn a_lost_hub_fails_the_questions_it_had_not_answered() {
    let (_root, mut actor, _hub_frames, mut cli_frames) = satellite().await;
    register_hub(&mut actor);
    handled(actor.try_handle_hub_reverse_request(
        CLI,
        9,
        "hub.forward",
        &json!({"type": "project.list"}),
    ));

    actor.forget_hub_reverse_client(HUB);

    let failure = cli_frames.try_recv().unwrap().as_json().unwrap();
    assert_eq!(failure["id"], 9, "{failure}");
    assert_eq!(failure["ok"], false, "{failure}");
    assert!(
        failure["error"]
            .as_str()
            .unwrap()
            .contains("No Alera desktop"),
        "{failure}"
    );
    let status =
        handled(actor.try_handle_hub_reverse_request(CLI, 2, "hub.link.status", &json!({})));
    assert_eq!(status["linked"], false);
}

#[tokio::test]
async fn the_reverse_channel_is_closed_to_phones_and_ignores_other_verbs() {
    let (_root, mut actor, _hub_frames, _cli_frames) = satellite().await;
    assert!(actor
        .try_handle_hub_reverse_request(PHONE, 1, "hub.link.register", &json!({}))
        .is_err());
    assert!(actor
        .try_handle_hub_reverse_request(CLI, 1, "project.list", &json!({}))
        .unwrap()
        .is_none());
}

#[tokio::test]
async fn the_satellite_refuses_to_forward_what_the_hub_would_not_answer() {
    let (_root, mut actor, mut hub_frames, _cli_frames) = satellite().await;
    register_hub(&mut actor);
    for refused in [
        "host.process.run",
        "terminal.create",
        "sshTarget.list",
        "hostLink.status",
        "project.register",
    ] {
        let error = actor
            .try_handle_hub_reverse_request(
                CLI,
                4,
                "hub.forward",
                &json!({"type": refused, "payload": {}}),
            )
            .unwrap_err();
        assert!(
            error.to_string().contains("cannot ask") && error.to_string().contains("desktop"),
            "{refused}: {error}"
        );
    }
    assert!(
        hub_frames.try_recv().is_err(),
        "nothing reached the hub for a refused verb"
    );
}

#[tokio::test]
async fn transparent_forwarding_needs_a_satellite_a_local_stranger_and_an_admitted_verb() {
    let (_root, mut actor, mut hub_frames, _cli_frames) = satellite().await;
    let payload = json!({"projectId": "p1", "name": "From the terminal"});

    assert!(
        !actor
            .try_forward_to_hub(CLI, 10, "workspace.createShared", &payload)
            .await
            .unwrap(),
        "an ordinary runtime handles the verb itself"
    );

    // Mirroring is what makes this runtime a satellite, and it arrives over a
    // registered hub link, so the cached "no" from above must not survive it.
    register_hub(&mut actor);
    mark_as_satellite(&actor).await;
    assert!(!actor
        .try_forward_to_hub(HUB, 11, "hub.mirror.workspace", &json!({}))
        .await
        .unwrap());

    assert!(actor
        .try_forward_to_hub(CLI, 12, "workspace.createShared", &payload)
        .await
        .unwrap());
    let asked = hub_frames.try_recv().unwrap().as_json().unwrap();
    assert_eq!(asked["event"], HUB_REQUEST_EVENT, "{asked}");
    assert_eq!(asked["payload"]["type"], "workspace.createShared");
    assert_eq!(asked["payload"]["payload"], payload, "sent as it came");

    assert!(
        !actor
            .try_forward_to_hub(HUB, 13, "workspace.createShared", &payload)
            .await
            .unwrap(),
        "the hub's own requests are handled here"
    );
    assert!(
        !actor
            .try_forward_to_hub(PHONE, 14, "workspace.createShared", &payload)
            .await
            .unwrap(),
        "a phone never reaches the hub through a satellite"
    );
    for local_verb in [
        "sshTarget.list",
        "workspace.files.list",
        "git.status",
        "status.get",
        "workspace.runSetup",
        "terminal.ownerLifecycle",
    ] {
        assert!(
            !actor
                .try_forward_to_hub(CLI, 15, local_verb, &json!({}))
                .await
                .unwrap(),
            "{local_verb} stays on the satellite"
        );
    }
    assert!(
        !actor
            .try_forward_to_hub(
                CLI,
                16,
                "workspace.removeShared",
                &json!({"id": "task", "expectedInstanceId": "task-instance", "closeSessions": true}),
            )
            .await
            .unwrap(),
        "the owner's retirement of this host's copy runs here"
    );
    assert!(
        hub_frames.try_recv().is_err(),
        "only the one admitted question reached the hub"
    );
    assert!(actor
        .try_forward_to_hub(
            CLI,
            17,
            "workspace.bufferGuard.release",
            &json!({"guardId": "acquired-on-the-hub"}),
        )
        .await
        .unwrap());
    let released = hub_frames.try_recv().unwrap().as_json().unwrap();
    assert_eq!(released["payload"]["type"], "workspace.bufferGuard.release");
}

#[tokio::test]
async fn a_satellite_without_a_hub_refuses_instead_of_acting_on_its_copies() {
    let (_root, mut actor, _hub_frames, _cli_frames) = satellite().await;
    mark_as_satellite(&actor).await;
    let error = actor
        .try_forward_to_hub(
            CLI,
            20,
            "workspace.createShared",
            &json!({"projectId": "p1"}),
        )
        .await
        .unwrap_err();
    assert!(
        error.to_string().contains("No Alera desktop is linked"),
        "{error}"
    );
}

#[tokio::test]
async fn a_hub_reply_keeps_the_error_shape_of_a_normal_response() {
    let (_root, mut actor, mut hub_frames, mut cli_frames) = satellite().await;
    register_hub(&mut actor);
    mark_as_satellite(&actor).await;

    async fn ask(
        actor: &mut ServerActor,
        hub_frames: &mut tokio::sync::mpsc::UnboundedReceiver<super::super::ClientFrame>,
        request_id: i64,
    ) -> String {
        assert!(actor
            .try_forward_to_hub(CLI, request_id, "workspace.find", &json!({"id": "w1"}))
            .await
            .unwrap());
        let asked = hub_frames.try_recv().unwrap().as_json().unwrap();
        asked["payload"]["requestId"].as_str().unwrap().to_string()
    }

    let reverse_id = ask(&mut actor, &mut hub_frames, 30).await;
    handled(actor.try_handle_hub_reverse_request(
        HUB,
        1,
        "hub.respond",
        &json!({"requestId": reverse_id, "ok": false, "error": "FormatException: Workspace id is required."}),
    ));
    let format = cli_frames.try_recv().unwrap().as_json().unwrap();
    assert_eq!(format["id"], 30);
    assert_eq!(
        format["error"],
        "FormatException: Workspace id is required."
    );

    let reverse_id = ask(&mut actor, &mut hub_frames, 31).await;
    handled(actor.try_handle_hub_reverse_request(
        HUB,
        2,
        "hub.respond",
        &json!({"requestId": reverse_id, "ok": false, "error": "stale",
            "errorCode": "gitError", "errorDetails": {"kind": "conflict"}}),
    ));
    let conflict = cli_frames.try_recv().unwrap().as_json().unwrap();
    assert_eq!(conflict["id"], 31);
    assert_eq!(conflict["errorCode"], "gitError", "{conflict}");
    assert_eq!(conflict["errorDetails"]["kind"], "conflict", "{conflict}");
}
