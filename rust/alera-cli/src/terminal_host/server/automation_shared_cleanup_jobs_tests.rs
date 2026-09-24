use super::*;
use crate::terminal_host::server::ServerCommand;
use serde_json::Value;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

async fn actions(actor: &ServerActor, run: &AutomationRun) -> Vec<String> {
    actor
        .runtime_store
        .list_automation_audit_events(Some(&run.automation_id), 100)
        .await
        .unwrap()
        .into_iter()
        .map(|event| event.action)
        .collect()
}

async fn finish(actor: &mut ServerActor, command: ServerCommand) {
    let ServerCommand::AutomationSharedCleanupFinished { attempt, result } = command else {
        panic!("Unexpected cleanup command")
    };
    actor
        .finish_automation_shared_cleanup(&attempt, result)
        .await;
}

#[tokio::test]
async fn default_preserve_policy_never_starts_a_cleanup_job() {
    let (_root, mut actor, run) = successful().await;
    let mut definition = actor
        .runtime_store
        .find_automation(&run.automation_id)
        .await
        .unwrap()
        .unwrap();
    definition.cleanup_policy = None;
    actor
        .runtime_store
        .upsert_automation(definition.clone(), definition.modified_by)
        .await
        .unwrap();
    actor
        .cleanup_automation_owned_target(&run, AutomationRunStatus::Success)
        .await;
    assert_eq!(actor.managed_workspace_jobs, 0);
    assert!(!actions(&actor, &run)
        .await
        .iter()
        .any(|action| action.starts_with("cleanup")));
    assert!(actor
        .runtime_store
        .find_workspace("owned")
        .await
        .unwrap()
        .is_some());
}

#[tokio::test]
async fn unavailable_runtime_records_unverified_cleanup_and_releases_job_lifetime() {
    let (_root, mut actor, run) = successful().await;
    let (sender, mut receiver) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = sender;
    actor
        .cleanup_automation_owned_target(&run, AutomationRunStatus::Success)
        .await;
    assert_eq!(actor.managed_workspace_jobs, 1);
    let command = tokio::time::timeout(std::time::Duration::from_secs(5), receiver.recv())
        .await
        .unwrap()
        .unwrap();
    finish(&mut actor, command).await;
    assert_eq!(actor.managed_workspace_jobs, 0);
    let actions = actions(&actor, &run).await;
    assert!(actions.contains(&"cleanupRequested".into()));
    assert!(actions.contains(&"cleanupUnverified".into()));
    assert!(!actions.contains(&"cleanupCompleted".into()));
    assert!(actor
        .runtime_store
        .find_workspace("owned")
        .await
        .unwrap()
        .is_some());
}

#[tokio::test]
async fn cleanup_job_uses_loopback_buffer_handshake_and_refuses_dirty_editors() {
    use crate::terminal_host::protocol::*;
    let (root, mut actor, run) = successful().await;
    let workspace = actor
        .runtime_store
        .find_workspace("owned")
        .await
        .unwrap()
        .unwrap();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    std::fs::write(root.path().join("runtime-host.json"), json!({
        "protocolVersion":PROTOCOL_VERSION,"port":listener.local_addr().unwrap().port(),"token":"test-token",
        "runtimeCapabilities":[RUNTIME_HOST_CAPABILITY,RUNTIME_HOST_BOOTSTRAP_CAPABILITY,RUNTIME_HOST_MANAGED_WORKSPACE_CAPABILITY,RUNTIME_HOST_SHARED_CHECKOUT_CAPABILITY]
    }).to_string()).unwrap();
    let fixture = tokio::spawn(async move {
        let (socket, _) = listener.accept().await.unwrap();
        let (reader, mut writer) = socket.into_split();
        let mut lines = BufReader::new(reader).lines();
        for expected in [
            "hello",
            "workspace.bufferGuard.acquire",
            "workspace.bufferGuard.release",
        ] {
            let request: Value =
                serde_json::from_str(&lines.next_line().await.unwrap().unwrap()).unwrap();
            assert_eq!(request["type"], expected);
            let response = match expected {
                "hello" => {
                    assert_eq!(request["payload"]["token"], "test-token");
                    json!({})
                }
                "workspace.bufferGuard.acquire" => {
                    assert_eq!(request["payload"]["id"], "owned");
                    assert_eq!(
                        request["payload"]["expectedInstanceId"],
                        workspace.instance_id
                    );
                    assert_eq!(request["payload"]["operation"], "removeShared");
                    json!({"guardId":"guard","workspaceInstanceId":workspace.instance_id,"ready":false,"disconnectedClients":0,"blockers":[{"path":"notes.md","reason":"Unsaved changes"}]})
                }
                _ => json!({}),
            };
            writer
                .write_all(
                    format!(
                        "{}\n",
                        json!({"id":request["id"],"ok":true,"payload":response})
                    )
                    .as_bytes(),
                )
                .await
                .unwrap();
        }
        assert!(lines.next_line().await.unwrap().is_none());
    });
    let (sender, mut receiver) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = sender;
    actor
        .cleanup_automation_owned_target(&run, AutomationRunStatus::Success)
        .await;
    let command = tokio::time::timeout(std::time::Duration::from_secs(5), receiver.recv())
        .await
        .unwrap()
        .unwrap();
    finish(&mut actor, command).await;
    fixture.await.unwrap();
    assert!(actor
        .runtime_store
        .find_workspace("owned")
        .await
        .unwrap()
        .is_some());
    assert!(actions(&actor, &run)
        .await
        .contains(&"cleanupUnverified".into()));
    assert_eq!(actor.managed_workspace_jobs, 0);
}

#[tokio::test]
async fn lost_response_is_completed_only_when_exact_retirement_receipt_exists() {
    let (_root, mut actor, run) = successful().await;
    let workspace = actor
        .runtime_store
        .find_workspace("owned")
        .await
        .unwrap()
        .unwrap();
    actor
        .runtime_store
        .request_automation_shared_cleanup(&run, &workspace, Utc::now())
        .await
        .unwrap();
    let attempt = actor
        .runtime_store
        .claim_automation_shared_cleanup(&run.id, Utc::now())
        .await
        .unwrap()
        .unwrap();
    let request = mutation(&mut actor, &run).await;
    actor.prepare_runtime_mutation(&request).await.unwrap();
    assert!(run_runtime_mutation(actor.runtime_store.clone(), request)
        .await
        .result
        .is_ok());
    actor.managed_workspace_jobs = 1;
    actor
        .finish_automation_shared_cleanup(&attempt, Err("Lost response".into()))
        .await;
    assert!(actions(&actor, &run)
        .await
        .contains(&"cleanupCompleted".into()));
    assert_eq!(actor.managed_workspace_jobs, 0);
}

#[tokio::test]
async fn audit_failure_prevents_starting_cleanup() {
    let (_root, mut actor, run) = successful().await;
    sqlx::query("CREATE TRIGGER rejectCleanupAudit BEFORE INSERT ON automationAuditEvents WHEN NEW.action = 'cleanupRequested' BEGIN SELECT RAISE(ABORT, 'injected audit failure'); END")
        .execute(actor.runtime_store.pool()).await.unwrap();
    actor
        .cleanup_automation_owned_target(&run, AutomationRunStatus::Success)
        .await;
    assert_eq!(actor.managed_workspace_jobs, 0);
    assert!(actor
        .runtime_store
        .find_workspace("owned")
        .await
        .unwrap()
        .is_some());
}

async fn interrupted(actor: &ServerActor, run: &AutomationRun) -> AutomationCleanupAttempt {
    let workspace = actor
        .runtime_store
        .find_workspace("owned")
        .await
        .unwrap()
        .unwrap();
    let now = Utc::now();
    actor
        .runtime_store
        .request_automation_shared_cleanup(run, &workspace, now)
        .await
        .unwrap();
    let attempt = actor
        .runtime_store
        .claim_automation_shared_cleanup(&run.id, now)
        .await
        .unwrap()
        .unwrap();
    sqlx::query("UPDATE automationSharedCleanupIntents SET readyAt = 0 WHERE runId = ?")
        .bind(&run.id)
        .execute(actor.runtime_store.pool())
        .await
        .unwrap();
    attempt
}

async fn cleanup_state(actor: &ServerActor, run: &AutomationRun) -> String {
    sqlx::query_scalar("SELECT state FROM automationSharedCleanupIntents WHERE runId = ?")
        .bind(&run.id)
        .fetch_one(actor.runtime_store.pool())
        .await
        .unwrap()
}

#[tokio::test]
async fn recovery_reconciles_completed_retirement_without_starting_a_job() {
    let (root, mut actor, run) = successful().await;
    let attempt = interrupted(&actor, &run).await;
    actor
        .runtime_store
        .retire_verified_automation_shared_workspace(&run, &attempt.workspace)
        .await
        .unwrap();
    actor.runtime_store = RuntimeStore::open(root.path()).await.unwrap();
    actor.recover_automation_shared_cleanups().await;
    assert_eq!(actor.managed_workspace_jobs, 0);
    assert_eq!(cleanup_state(&actor, &run).await, "completed");
    assert!(actions(&actor, &run)
        .await
        .contains(&"cleanupCompleted".into()));
}

#[tokio::test]
async fn recovery_preserves_a_task_taken_over_while_runtime_was_stopped() {
    let (root, mut actor, mut run) = successful().await;
    interrupted(&actor, &run).await;
    run.taken_over = true;
    actor.runtime_store.save_automation_run(&run).await.unwrap();
    actor.runtime_store = RuntimeStore::open(root.path()).await.unwrap();
    actor.recover_automation_shared_cleanups().await;
    assert_eq!(actor.managed_workspace_jobs, 0);
    assert_eq!(cleanup_state(&actor, &run).await, "preserved");
    assert!(actor
        .runtime_store
        .find_workspace("owned")
        .await
        .unwrap()
        .is_some());
}

#[tokio::test]
async fn recovery_retries_once_and_leaves_unavailable_runtime_pending() {
    let (root, mut actor, run) = successful().await;
    let old = interrupted(&actor, &run).await;
    actor.runtime_store = RuntimeStore::open(root.path()).await.unwrap();
    let (sender, mut receiver) = tokio::sync::mpsc::unbounded_channel();
    actor.inbox = sender;
    actor.recover_automation_shared_cleanups().await;
    actor.recover_automation_shared_cleanups().await;
    assert_eq!(actor.managed_workspace_jobs, 1);
    let command = tokio::time::timeout(std::time::Duration::from_secs(5), receiver.recv())
        .await
        .unwrap()
        .unwrap();
    finish(&mut actor, command).await;
    assert_eq!(cleanup_state(&actor, &run).await, "pending");
    assert!(!actor
        .runtime_store
        .settle_automation_shared_cleanup(&old, false, None, Utc::now())
        .await
        .unwrap());
    assert!(actor
        .runtime_store
        .has_pending_automation_work()
        .await
        .unwrap());
    assert_eq!(actor.managed_workspace_jobs, 0);
}
