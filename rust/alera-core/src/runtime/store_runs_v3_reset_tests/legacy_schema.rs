use sqlx::sqlite::SqliteConnectOptions;

use super::{drop_v3_orchestration, execute, profile, schema, RuntimeStore, VERSION_KEY};
use crate::runtime::store_runs_v3_reset::RUNS_V3_BACKUP_FILE_NAME;

const LEGACY_TABLES: &str = include_str!("legacy_v2_tables.sql");

async fn rewind_complete_v2(store: &RuntimeStore, populated: bool) {
    let mut conn = store.pool().acquire().await.unwrap();
    drop_v3_orchestration(&mut conn).await;
    sqlx::raw_sql(LEGACY_TABLES)
        .execute(&mut *conn)
        .await
        .unwrap();
    execute(
        &mut conn,
        &[
            "CREATE TRIGGER workflowWorkspaceRecordProtected BEFORE DELETE ON workflowWorkspaces
                BEGIN SELECT RAISE(ABORT, 'workflow resources require reviewed cleanup'); END",
            "CREATE TRIGGER workflowLaunchTabRetained BEFORE DELETE ON workspaceTabs
                WHEN EXISTS(SELECT 1 FROM workflowWorkspaces WHERE id = OLD.workspaceId)
                BEGIN SELECT RAISE(ABORT, 'workflow terminals require reviewed cleanup'); END",
            "CREATE VIEW orchestrationBoardRuns AS SELECT id FROM orchestrationCoordinatorRuns",
            "UPDATE runtimeMetadata SET value = '2' WHERE key = 'orchestration.schemaVersion'",
        ],
    )
    .await;
    if !populated {
        return;
    }
    execute(
        &mut conn,
        &[
            "INSERT INTO projects (id, name, repoPath, createdAt, updatedAt, kind)
                VALUES ('project_keep', 'Keep', '/tmp/keep', '2026-01-01', '2026-01-01', 'git')",
            "INSERT INTO workspaces (id, instanceId, hostId, projectId, name, path, createdAt, updatedAt, kind, status)
                VALUES ('ws_keep', 'instance_keep', 'local', 'project_keep', 'Keep', '/tmp/keep', '2026-01-01', '2026-01-01', 'worktree', 'active')",
            "INSERT INTO workspaceTabs (id, workspaceId, kind, title, createdAt, updatedAt)
                VALUES ('tab_keep', 'ws_keep', 'terminal', 'Keep', '2026-01-01', '2026-01-01')",
            "INSERT INTO orchestrationCoordinatorRuns (id, spec, workspace_id)
                VALUES ('run_old', 'Reset', 'ws_keep')",
            "INSERT INTO orchestrationTasks (id, spec, run_id, workspace_id, coordinator_handle)
                VALUES ('task_old', 'Reset', 'run_old', 'ws_keep', 'coord')",
            "INSERT INTO orchestrationDispatchContexts (id, task_id, run_id, workspace_id, coordinator_handle)
                VALUES ('dispatch_old', 'task_old', 'run_old', 'ws_keep', 'coord')",
            "INSERT INTO workflowRuns (run_id, workspace_id, revision, status, integration_sha)
                VALUES ('run_old', 'ws_keep', 1, 'approved', 'sha')",
            "INSERT INTO workflowDecisions (id, run_id, revision, scope, decision, reason, plan_digest, evidence_digest, integration_sha)
                VALUES ('decision_old', 'run_old', 1, 'plan', 'approved', '', 'plan', 'evidence', 'sha')",
            "INSERT INTO workflowStageGates (run_id, revision, stage_id, decision_id)
                VALUES ('run_old', 1, 'build', 'decision_old')",
            "INSERT INTO workflowPlanTasks (task_id, run_id, revision, logical_id, frozen_task)
                VALUES ('task_old', 'run_old', 1, 'build', '{}')",
            "INSERT INTO workflowTaskEvidence (task_id, result_digest, artifact_digest, integration_sha)
                VALUES ('task_old', 'result', 'artifact', 'sha')",
            "INSERT INTO workflowWorkspaces (id, run_id, revision, attempt, path, identity, phase)
                VALUES ('ws_keep', 'run_old', 1, 1, '/tmp/keep', '{}', 'ready')",
            "INSERT INTO workflowWorkspaceRequests VALUES ('request_old', 'digest', 'ws_keep')",
            "INSERT INTO workflowCleanup (id, run_id, digest, document, expires_at, state)
                VALUES ('cleanup_old', 'run_old', 'digest', '{}', 0, 'preview')",
            "INSERT INTO workflowCleanupResources (workspace_id, cleanup_id)
                VALUES ('ws_keep', 'cleanup_old')",
            "INSERT INTO workflowPlanRevisions (run_id, revision, request_id, request_digest, snapshot, digest)
                VALUES ('run_old', 1, 'plan_old', 'digest', '{}', 'digest')",
            "INSERT INTO workflowApprovalChallenges (nonce, run_id, audience, statement, expires_at)
                VALUES ('nonce_old', 'run_old', 'desktop', '{}', 0)",
            "INSERT INTO workflowExecution VALUES ('run_old', 1, 1, 'paused')",
            "INSERT INTO workflowExecutionCommands (request_id, request_digest, run_id, receipt)
                VALUES ('execution_old', 'digest', 'run_old', '{}')",
            "INSERT INTO workflowExecutionIssues VALUES ('run_old', 1, 1, 'Paused')",
            "INSERT INTO workflowLaunches (id, request_id, request_digest, request, run_id, revision, task_id,
                workspace_id, terminal_handle, dispatch_id, base_sha, profile_id, profile_revision, inputs, context_hash, status)
                VALUES ('launch_old', 'launch_request', 'digest', '{}', 'run_old', 1, 'task_old',
                        'ws_keep', 'tab_keep', 'dispatch_old', 'sha', 'prof_keep', 0, '{}', 'hash', 'started')",
            "INSERT INTO workflowIntegrations (id, request_id, request_digest, run_id, revision, task_id, workspace_id, request, state)
                VALUES ('integration_old', 'integration_request', 'digest', 'run_old', 1, 'task_old', 'ws_keep', '{}', 'pending')",
            "INSERT INTO workflowProposalDrafts (id, request_digest, document)
                VALUES ('proposal_old', 'digest', '{}')",
            "INSERT INTO workflowCoordinators (proposal_id, tab_id, workspace_id, status)
                VALUES ('proposal_old', 'coord_old', 'ws_keep', 'started')",
            "INSERT INTO workflowProposalCancellations (proposal_id, workspace_id, status)
                VALUES ('proposal_old', 'ws_keep', 'pending')",
            "INSERT INTO workflowCancellationTargets (id, launch_id, run_id, state)
                VALUES ('cancellation_old', 'launch_old', 'run_old', 'pending')",
            "INSERT INTO workflowTerminalShutdowns VALUES ('tab_keep', 'ws_keep', 'started')",
            "INSERT INTO orchestrationBoardRevision VALUES (1, 1)",
            "INSERT INTO orchestrationDecisionGates (id, task_id, question)
                VALUES ('gate_old', 'task_old', 'Reset?')",
            "INSERT INTO orchestrationAuditEvents (id, action, reason)
                VALUES ('audit_old', 'create', 'Reset')",
            "INSERT INTO personalWorkflowRecipes VALUES ('recipe_keep', 1, 'id: recipe_keep')",
            "INSERT INTO orchestrationMessages (id, from_handle, to_handle, subject, type)
                VALUES ('inbox_keep', 'ext:user', 'coord', 'Keep', 'decision_gate'),
                       ('message_old', 'coord', 'worker', 'Reset', 'status')",
        ],
    )
    .await;
}

async fn assert_integrity(store: &RuntimeStore) {
    let mut conn = store.pool().acquire().await.unwrap();
    let checks: Vec<String> = sqlx::query_scalar("PRAGMA quick_check")
        .fetch_all(&mut *conn)
        .await
        .unwrap();
    assert_eq!(checks, ["ok"]);
    assert!(sqlx::query("PRAGMA foreign_key_check")
        .fetch_all(&mut *conn)
        .await
        .unwrap()
        .is_empty());
    let enabled: i64 = sqlx::query_scalar("PRAGMA foreign_keys")
        .fetch_one(&mut *conn)
        .await
        .unwrap();
    assert_eq!(enabled, 1);
}

async fn complete_v2_resets(populated: bool) {
    let fresh_dir = tempfile::tempdir().unwrap();
    let fresh = RuntimeStore::open(fresh_dir.path()).await.unwrap();
    let fresh_schema = schema(&fresh).await;
    fresh.pool().close().await;

    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    store.upsert_agent_profile(profile(), None).await.unwrap();
    rewind_complete_v2(&store, populated).await;
    assert_integrity(&store).await;
    store.pool().close().await;

    let store = RuntimeStore::open_as_runtime_owner(dir.path())
        .await
        .unwrap();
    assert_eq!(
        store.get_metadata(VERSION_KEY).await.unwrap().as_deref(),
        Some("3")
    );
    assert_eq!(schema(&store).await, fresh_schema);
    assert_integrity(&store).await;
    assert!(store
        .find_agent_profile("prof_keep")
        .await
        .unwrap()
        .is_some());
    assert!(store
        .list_orchestration_tasks(None)
        .await
        .unwrap()
        .is_empty());
    assert!(store
        .list_orchestration_coordinator_runs(None)
        .await
        .unwrap()
        .is_empty());
    if populated {
        let kept: (String, String, String, String) = sqlx::query_as(
            "SELECT p.id, w.id, t.id, r.id FROM projects p JOIN workspaces w ON w.projectId = p.id
             JOIN workspaceTabs t ON t.workspaceId = w.id CROSS JOIN personalRecipes r",
        )
        .fetch_one(store.pool())
        .await
        .unwrap();
        assert_eq!(
            kept,
            (
                "project_keep".into(),
                "ws_keep".into(),
                "tab_keep".into(),
                "recipe_keep".into()
            )
        );
        let message = store
            .orchestration_message_by_id("inbox_keep")
            .await
            .unwrap()
            .unwrap();
        assert_eq!(
            message.message_type,
            crate::runtime::OrchestrationMessageType::Question
        );
        assert!(store
            .orchestration_message_by_id("message_old")
            .await
            .unwrap()
            .is_none());
    }

    let backup = sqlx::SqlitePool::connect_with(
        SqliteConnectOptions::new()
            .filename(dir.path().join(RUNS_V3_BACKUP_FILE_NAME))
            .read_only(true),
    )
    .await
    .unwrap();
    let version: String = sqlx::query_scalar("SELECT value FROM runtimeMetadata WHERE key = ?")
        .bind(VERSION_KEY)
        .fetch_one(&backup)
        .await
        .unwrap();
    assert_eq!(version, "2");
    let old: (i64, i64, i64, i64) = sqlx::query_as(
        "SELECT (SELECT COUNT(*) FROM orchestrationTasks),
                (SELECT COUNT(*) FROM orchestrationDispatchContexts),
                (SELECT COUNT(*) FROM workflowDecisions), (SELECT COUNT(*) FROM workflowStageGates)",
    ).fetch_one(&backup).await.unwrap();
    let count = i64::from(populated);
    assert_eq!(old, (count, count, count, count));
    assert!(sqlx::query("PRAGMA foreign_key_check")
        .fetch_all(&backup)
        .await
        .unwrap()
        .is_empty());
    backup.close().await;
    store.pool().close().await;
}

#[tokio::test]
async fn complete_empty_v2_schema_resets_without_dangling_foreign_keys() {
    complete_v2_resets(false).await;
}

#[tokio::test]
async fn complete_populated_v2_schema_resets_and_backs_up_legacy_records() {
    complete_v2_resets(true).await;
}

#[tokio::test]
async fn cyclic_legacy_foreign_keys_refuse_the_reset_without_changing_data() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    rewind_complete_v2(&store, true).await;
    let mut conn = store.pool().acquire().await.unwrap();
    execute(&mut conn, &[
        "CREATE TABLE workflowCycleA (id TEXT PRIMARY KEY, b_id TEXT REFERENCES workflowCycleB(id))",
        "CREATE TABLE workflowCycleB (id TEXT PRIMARY KEY, a_id TEXT REFERENCES workflowCycleA(id))",
    ]).await;
    drop(conn);
    let before = schema(&store).await;
    let error = store
        .migrate_orchestration_v3(Some(dir.path()), true)
        .await
        .unwrap_err();
    assert!(error.to_string().contains("cyclic foreign keys"), "{error}");
    assert_eq!(
        store.get_metadata(VERSION_KEY).await.unwrap().as_deref(),
        Some("2")
    );
    assert_eq!(schema(&store).await, before);
    let kept: (i64, i64) = sqlx::query_as(
        "SELECT (SELECT COUNT(*) FROM workflowDecisions), (SELECT COUNT(*) FROM orchestrationTasks)",
    ).fetch_one(store.pool()).await.unwrap();
    assert_eq!(kept, (1, 1));
    assert_integrity(&store).await;
    assert!(dir.path().join(RUNS_V3_BACKUP_FILE_NAME).exists());
    store.pool().close().await;
}

#[tokio::test]
async fn extra_legacy_tables_resolve_case_insensitive_and_self_references() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    rewind_complete_v2(&store, true).await;
    let mut conn = store.pool().acquire().await.unwrap();
    execute(&mut conn, &[
        "CREATE TABLE workflowSelf (id TEXT PRIMARY KEY, parent_id TEXT REFERENCES workflowSelf(id) ON DELETE CASCADE)",
        "INSERT INTO workflowSelf VALUES ('self', 'self')",
        "CREATE TABLE \"workflowQuoted\"\"Child\" (run_id TEXT REFERENCES WORKFLOWRUNS(run_id))",
        "INSERT INTO \"workflowQuoted\"\"Child\" VALUES ('run_old')",
    ]).await;
    drop(conn);
    store.pool().close().await;
    let store = RuntimeStore::open_as_runtime_owner(dir.path())
        .await
        .unwrap();
    assert_integrity(&store).await;
    assert_eq!(
        store.get_metadata(VERSION_KEY).await.unwrap().as_deref(),
        Some("3")
    );
    store.pool().close().await;
}
