use std::collections::HashMap;

use serde_json::Value;

use super::super::actor_test_harness::test_actor;
use crate::terminal_host::control_file;
use crate::terminal_host::protocol::TerminalHostConfig;

#[tokio::test]
async fn promotion_keeps_actor_state_and_cannot_be_downgraded() {
    let dir = tempfile::tempdir().unwrap();
    let mut actor = test_actor(&dir, HashMap::new(), HashMap::new()).await;
    control_file::write_control_file(&actor.control_file_path, 45678, "token", false).unwrap();
    actor.managed_workspace_jobs = 2;
    actor.shutdown_gen = 7;

    let response = actor.promote_persistent().unwrap();

    assert_eq!(response["persistent"], true);
    assert!(actor.config.persistent);
    assert_eq!(actor.managed_workspace_jobs, 2);
    assert!(actor.shutdown_gen > 7);
    let control: Value =
        serde_json::from_str(&std::fs::read_to_string(&actor.control_file_path).unwrap()).unwrap();
    assert_eq!(control["persistent"], true);

    actor.apply_config(TerminalHostConfig::default()).await;
    assert!(actor.config.persistent);
    assert_eq!(actor.managed_workspace_jobs, 2);
}
