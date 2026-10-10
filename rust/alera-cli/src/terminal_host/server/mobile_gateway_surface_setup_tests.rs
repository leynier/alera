use std::collections::HashMap;

use super::super::actor_test_harness::{mobile_client, test_actor};
use super::*;
use crate::terminal_host::client::ClientHandle;

/// Recovery's "Run Saved Setup" on the phone sends `workspace.runSetup`, next
/// to the relocation setup verbs it already could call.
#[test]
fn mobile_may_run_saved_workspace_setup() {
    for request in [
        "workspace.runSetup",
        "workspace.prepareRelocationSetup",
        "workspace.recoverRelocationSetup",
        "workspace.cancelRelocationSetup",
    ] {
        assert!(mobile_request_allowed(request), "{request}");
    }
}

#[tokio::test]
async fn a_paired_phone_passes_the_request_gate_for_run_setup() {
    let dir = tempfile::tempdir().unwrap();
    let (handle, _) = ClientHandle::test_channels();
    let actor = test_actor(
        &dir,
        HashMap::from([(7, mobile_client(handle, "phone"))]),
        HashMap::new(),
    )
    .await;

    actor
        .require_request_allowed(7, "workspace.runSetup")
        .expect("mobile Run Saved Setup reaches its handler");
    assert!(actor
        .require_request_allowed(7, "runtimeMetadata.set")
        .is_err());
}
