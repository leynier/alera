use clap::Parser;
use serde_json::json;

use super::*;
use crate::cli::Cli;

fn parses(arguments: &[&str]) -> bool {
    Cli::try_parse_from(["alera", "orchestration"].iter().chain(arguments)).is_ok()
}

#[test]
fn lifecycle_cli_offers_no_human_decision() {
    for arguments in [
        &["proposals", "approve", "--id", "p"][..],
        &["execution", "approve", "--run", "r"],
        &["cleanup", "decide", "--id", "c"],
        &["plans", "review"],
    ] {
        assert!(!parses(arguments), "{arguments:?}");
    }
    assert!(parses(&["proposals", "start-coordinator", "--id", "p"]));
    assert!(parses(&["cleanup", "apply", "--id", "c", "--digest", "d"]));
    assert!(!parses(&["cleanup", "preview", "--run", "r"]));
    assert!(!parses(&["proposals", "list", "--before-id", "x"]));
}

#[test]
fn proposal_document_freezes_the_source_and_maps_roles() {
    let args = WorkflowProposalCreateArgs {
        workspace_id: "ws".into(),
        recipe_source: r#"{"origin":"builtIn","id":"quick-fix"}"#.into(),
        recipe_digest: "d".into(),
        coordinator_profile_id: "prof_c".into(),
        role_profiles: vec!["builder=prof_b".into()],
        max_concurrent: 2,
        run: None,
        expected_revision: None,
        request_id: "request-1".into(),
        objective: None,
        objective_stdin: false,
    };
    let source = json!({"workspace": {"workspaceId": "ws"}, "sha": "abc"});
    let document: Value =
        serde_json::from_str(&proposal_document(&args, "Ship it".into(), &source).unwrap())
            .unwrap();
    assert_eq!(document["expectedSource"]["workspaceId"], "ws");
    let proposal = &document["request"]["proposal"];
    assert_eq!(proposal["sourceSha"], "abc");
    assert_eq!(proposal["roleProfiles"]["builder"], "prof_b");
    assert_eq!(proposal["recipeSource"]["origin"], "builtIn");
    let invalid = WorkflowProposalCreateArgs {
        role_profiles: vec!["builder".into()],
        ..args
    };
    assert!(proposal_document(&invalid, "x".into(), &source).is_err());
}

#[test]
fn execution_and_cleanup_requests_wrap_their_documents() {
    let (verb, payload) = execution_request(
        WorkflowExecutionAction::Control {
            run: "r".into(),
            revision: 2,
            expected_sequence: 3,
            action: WorkflowExecutionVerb::Pause,
            request_id: "request-1".into(),
        },
        &mut std::io::empty(),
    )
    .unwrap();
    assert_eq!(verb, "workflows.controlExecution");
    let document: Value = serde_json::from_str(payload["document"].as_str().unwrap()).unwrap();
    assert_eq!(document["action"], "pause");
    let (verb, payload) = execution_request(
        WorkflowExecutionAction::Correct {
            run: "r".into(),
            revision: 2,
            plan_digest: "d".into(),
            request_id: "request-1".into(),
            reason: None,
            reason_stdin: true,
        },
        &mut "Fix the tests".as_bytes(),
    )
    .unwrap();
    assert_eq!(verb, "workflows.createCorrection");
    assert!(payload["document"]
        .as_str()
        .unwrap()
        .contains("Fix the tests"));
    let (verb, payload, _) = cleanup_request(WorkflowCleanupAction::Preview {
        run: "r".into(),
        workspaces: vec!["a".into(), "b".into()],
        remove_branches: vec!["b".into()],
        id: None,
    })
    .unwrap();
    assert_eq!(verb, "workflows.previewCleanup");
    let document: Value = serde_json::from_str(payload["document"].as_str().unwrap()).unwrap();
    assert_eq!(document["resources"][0]["removeBranch"], false);
    assert_eq!(document["resources"][1]["removeBranch"], true);
    assert!(cleanup_request(WorkflowCleanupAction::Preview {
        run: "r".into(),
        workspaces: vec!["a".into()],
        remove_branches: vec!["b".into()],
        id: None,
    })
    .is_err());
}
