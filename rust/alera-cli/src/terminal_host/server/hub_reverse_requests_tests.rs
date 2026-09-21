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

fn handled(outcome: HostResult<Option<ReverseOutcome>>) -> Value {
    match outcome.unwrap().expect("a reverse channel verb") {
        ReverseOutcome::Answer(value) => value,
        ReverseOutcome::Deferred => json!("deferred"),
    }
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

    handled(actor.try_handle_hub_reverse_request(HUB, 1, "hub.link.register", &json!({})));
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
    handled(actor.try_handle_hub_reverse_request(HUB, 1, "hub.link.register", &json!({})));
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
async fn the_hub_answers_reads_and_refuses_everything_else() {
    let directory = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(directory.path()).await.unwrap();
    let now = chrono::Utc::now();
    let project: alera_core::runtime::Project = serde_json::from_value(json!({
        "id": "p1", "name": "Alera", "repoPath": "/home/me/alera", "kind": "gitRepository",
        "createdAt": now, "updatedAt": now,
    }))
    .unwrap();
    store.upsert_project(project).await.unwrap();

    let projects = answer_reverse_request(&store, "ssh-a", "project.list", &json!({}))
        .await
        .unwrap();
    assert_eq!(projects["originHostId"], "ssh-a");
    assert_eq!(projects["items"][0]["id"], "p1");
    assert_eq!(projects["items"][0]["primaryHostId"], "local");

    let workspaces = answer_reverse_request(
        &store,
        "ssh-a",
        "workspace.list",
        &json!({"hostId": "origin"}),
    )
    .await
    .unwrap();
    assert_eq!(workspaces["items"], json!([]));

    for refused in [
        "workspace.remove",
        "host.process.run",
        "terminal.create",
        "sshTarget.list",
    ] {
        let error = answer_reverse_request(&store, "ssh-a", refused, &json!({}))
            .await
            .unwrap_err();
        assert!(
            error.to_string().contains("cannot ask"),
            "{refused}: {error}"
        );
    }
}
