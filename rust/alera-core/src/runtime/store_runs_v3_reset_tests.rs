use chrono::Utc;
use sqlx::Row;

use super::store_runs_v3_reset::RUNS_V3_BACKUP_FILE_NAME;
use super::{AgentProfile, AgentProfileLaunchMode, OrchestrationMessageType, RuntimeStore};

const VERSION_KEY: &str = "orchestration.schemaVersion";

#[path = "store_runs_v3_reset_tests/legacy_schema.rs"]
mod legacy_schema;

fn profile() -> AgentProfile {
    let now = Utc::now();
    AgentProfile {
        id: "prof_keep".into(),
        name: "Keeper".into(),
        sort_order: 0,
        agent_type: "codex".into(),
        command: "codex".into(),
        launch_mode: AgentProfileLaunchMode::Command,
        managed_config: None,
        custom_prompt: String::new(),
        description: String::new(),
        quota_group: None,
        show_in_new_tab_menu: false,
        revision: 0,
        created_at: now,
        updated_at: now,
    }
}

async fn execute(conn: &mut sqlx::SqliteConnection, statements: &[&str]) {
    for statement in statements {
        sqlx::query(sqlx::AssertSqlSafe(*statement))
            .execute(&mut *conn)
            .await
            .unwrap_or_else(|error| panic!("{statement}: {error}"));
    }
}

/// Every schema object except SQLite's own, as `type name sql`, sorted. The
/// SQL drops whitespace and quotes, which `ALTER TABLE ... RENAME` rewrites.
async fn schema(store: &RuntimeStore) -> Vec<String> {
    let mut objects: Vec<String> = sqlx::query(
        "SELECT type, name, COALESCE(sql, '') AS sql FROM sqlite_master \
         WHERE name NOT LIKE 'sqlite_%'",
    )
    .fetch_all(store.pool())
    .await
    .unwrap()
    .into_iter()
    .map(|row| {
        let sql: String = row.get("sql");
        let sql: String = sql
            .chars()
            .filter(|c| !c.is_whitespace() && *c != '"')
            .collect();
        format!(
            "{} {} {sql}",
            row.get::<String, _>("type"),
            row.get::<String, _>("name"),
        )
    })
    .collect();
    objects.sort();
    objects
}

/// Drops every v3 orchestration and run object, leaving the rest of a fresh
/// store, so a test can rebuild an older orchestration schema in its place.
pub(super) async fn drop_v3_orchestration(conn: &mut sqlx::SqliteConnection) {
    let objects: Vec<(String, String)> = sqlx::query(
        "SELECT type, name FROM sqlite_master WHERE type IN ('trigger','view','table') \
         AND (name LIKE 'orchestration%' OR (name LIKE 'run%' AND name NOT LIKE 'runtime%') \
           OR name LIKE 'board_%' \
           OR name LIKE 'inbox_messages_%' OR name LIKE 'conversation_messages_%' \
           OR name LIKE 'runtimeEventsTask%' OR name LIKE 'runtimeEventsQuestion%' \
           OR name = 'personalRecipes') \
         ORDER BY CASE type WHEN 'trigger' THEN 0 WHEN 'view' THEN 1 ELSE 2 END",
    )
    .fetch_all(&mut *conn)
    .await
    .unwrap()
    .into_iter()
    .map(|row| (row.get("type"), row.get("name")))
    .collect();
    sqlx::query("PRAGMA foreign_keys = OFF")
        .execute(&mut *conn)
        .await
        .unwrap();
    for (kind, name) in objects {
        let statement = format!("DROP {} IF EXISTS \"{name}\"", kind.to_uppercase());
        sqlx::query(sqlx::AssertSqlSafe(statement))
            .execute(&mut *conn)
            .await
            .unwrap();
    }
    sqlx::query("PRAGMA foreign_keys = ON")
        .execute(&mut *conn)
        .await
        .unwrap();
}

/// Replaces the v3 orchestration objects of a fresh store with a v2-shaped
/// store holding runs, a workflow, inbox traffic and a personal recipe.
async fn rewind_to_v2(store: &RuntimeStore) {
    let mut conn = store.pool().acquire().await.unwrap();
    drop_v3_orchestration(&mut conn).await;
    execute(
        &mut conn,
        &[
            "CREATE TABLE orchestrationMessages (
                id TEXT NOT NULL, from_handle TEXT NOT NULL, to_handle TEXT NOT NULL,
                subject TEXT NOT NULL, body TEXT NOT NULL DEFAULT '',
                type TEXT NOT NULL DEFAULT 'status'
                    CHECK(type IN ('status','dispatch','worker_done','merge_ready',
                                   'escalation','handoff','decision_gate','heartbeat')),
                priority TEXT NOT NULL DEFAULT 'normal', thread_id TEXT, payload TEXT,
                read INTEGER NOT NULL DEFAULT 0, sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                created_at TEXT NOT NULL DEFAULT (datetime('now')), delivered_at TEXT,
                run_id TEXT, workspace_id TEXT, task_id TEXT, dispatch_id TEXT,
                state TEXT NOT NULL DEFAULT 'queued', expires_at TEXT, obsolete_at TEXT,
                reply_to_id TEXT, external_meta TEXT)",
            "CREATE TABLE orchestrationTasks (
                id TEXT PRIMARY KEY, spec TEXT NOT NULL, status TEXT NOT NULL,
                run_id TEXT, workspace_id TEXT NOT NULL, coordinator_handle TEXT NOT NULL)",
            "CREATE TABLE orchestrationDecisionGates (
                id TEXT PRIMARY KEY, task_id TEXT NOT NULL, question TEXT NOT NULL,
                options TEXT NOT NULL DEFAULT '[]', status TEXT NOT NULL DEFAULT 'pending')",
            "CREATE TABLE orchestrationCoordinatorRuns (
                id TEXT PRIMARY KEY, spec TEXT NOT NULL,
                status TEXT NOT NULL CHECK(status IN ('idle','running','completed','failed','stopping','stopped')),
                workspace_id TEXT NOT NULL, execution_policy TEXT,
                execution_policy_status TEXT NOT NULL DEFAULT 'none')",
            "CREATE TABLE workflowRuns (
                run_id TEXT PRIMARY KEY REFERENCES orchestrationCoordinatorRuns(id) ON DELETE CASCADE,
                workspace_id TEXT NOT NULL, revision INTEGER NOT NULL, status TEXT NOT NULL)",
            "CREATE TABLE workflowWorkspaces (id TEXT PRIMARY KEY, run_id TEXT NOT NULL)",
            "CREATE TRIGGER workflowWorkspaceRecordProtected BEFORE DELETE ON workflowWorkspaces
                BEGIN SELECT RAISE(ABORT, 'workflow resources require reviewed cleanup'); END",
            "CREATE TRIGGER workflowLaunchTabRetained BEFORE DELETE ON workspaceTabs
                WHEN EXISTS(SELECT 1 FROM workflowWorkspaces WHERE id = OLD.workspaceId)
                BEGIN SELECT RAISE(ABORT, 'workflow terminals require reviewed cleanup'); END",
            "CREATE VIEW orchestrationBoardRuns AS SELECT id FROM orchestrationCoordinatorRuns",
            "CREATE TABLE personalWorkflowRecipes (
                id TEXT PRIMARY KEY NOT NULL,
                revision INTEGER NOT NULL CHECK(revision > 0),
                document TEXT NOT NULL CHECK(length(CAST(document AS BLOB)) <= 262144))",
            "INSERT INTO orchestrationCoordinatorRuns VALUES
                ('run_old', 'Ship it', 'running', 'ws', NULL, 'none'),
                ('run_flow', 'Workflow', 'idle', 'ws', NULL, 'approved')",
            "INSERT INTO workflowRuns VALUES ('run_flow', 'ws', 1, 'approved')",
            "INSERT INTO workflowWorkspaces VALUES ('wf_ws', 'run_flow')",
            "INSERT INTO orchestrationTasks VALUES ('task_old', 'Do work', 'blocked', 'run_old', 'ws', 'coord')",
            "INSERT INTO orchestrationDecisionGates (id, task_id, question) VALUES ('gate_old', 'task_old', 'Go?')",
            "INSERT INTO orchestrationMessages
                (id, from_handle, to_handle, subject, body, type, priority, external_meta, expires_at)
             VALUES
                ('q_keep', 'ext:user', 'term_1', 'Question', 'Ready?', 'decision_gate', 'high',
                 '{\"client\":\"desktop\"}', '2999-01-01 00:00:00'),
                ('beat_drop', 'ext:user', 'term_1', 'beat', '', 'heartbeat', 'normal', NULL, NULL),
                ('agent_drop', 'term_1', 'coord', 'done', 'finished', 'status', 'normal', NULL, NULL)",
            "INSERT INTO orchestrationMessages
                (id, from_handle, to_handle, subject, body, type, reply_to_id, thread_id, state, read)
             VALUES
                ('reply_keep', 'term_1', 'ext:user', 'Re: Question', 'Yes', 'status', 'q_keep', 'q_keep', 'delivered', 0)",
            "INSERT INTO personalWorkflowRecipes VALUES ('team-flow', 3, 'id: team-flow')",
            "UPDATE runtimeMetadata SET value = '2' WHERE key = 'orchestration.schemaVersion'",
        ],
    )
    .await;
}

#[tokio::test]
async fn v2_store_resets_to_v3_keeping_profiles_recipes_and_the_inbox() {
    let fresh_dir = tempfile::tempdir().unwrap();
    let fresh = RuntimeStore::open(fresh_dir.path()).await.unwrap();
    let fresh_schema = schema(&fresh).await;
    drop(fresh);

    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    store.upsert_agent_profile(profile(), None).await.unwrap();
    rewind_to_v2(&store).await;
    store.pool().close().await;
    drop(store);
    let key = dir.path().join("desktop-workflow-approval.key");
    std::fs::write(&key, b"retired").unwrap();

    let store = RuntimeStore::open_as_runtime_owner(dir.path())
        .await
        .unwrap();
    assert_eq!(
        store.get_metadata(VERSION_KEY).await.unwrap().as_deref(),
        Some("3")
    );
    assert!(dir.path().join(RUNS_V3_BACKUP_FILE_NAME).exists());
    assert!(!key.exists());

    assert!(store
        .find_agent_profile("prof_keep")
        .await
        .unwrap()
        .is_some());
    let recipes: Vec<(String, i64)> =
        sqlx::query_as("SELECT id, revision FROM personalRecipes ORDER BY id")
            .fetch_all(store.pool())
            .await
            .unwrap();
    assert_eq!(recipes, vec![("team-flow".to_string(), 3)]);

    let question = store
        .orchestration_message_by_id("q_keep")
        .await
        .unwrap()
        .expect("the inbox question survives");
    assert_eq!(question.message_type, OrchestrationMessageType::Question);
    assert_eq!(question.state, "queued");
    assert!(question.external_meta.is_some());
    let reply = store
        .orchestration_message_by_id("reply_keep")
        .await
        .unwrap()
        .expect("the reply to the inbox survives");
    assert_eq!(reply.reply_to_id.as_deref(), Some("q_keep"));
    assert_eq!(reply.state, "delivered");
    for dropped in ["beat_drop", "agent_drop"] {
        assert!(store
            .orchestration_message_by_id(dropped)
            .await
            .unwrap()
            .is_none());
    }

    assert!(store
        .list_orchestration_coordinator_runs(None)
        .await
        .unwrap()
        .is_empty());
    assert!(store
        .list_orchestration_gates(None, None)
        .await
        .unwrap()
        .is_empty());
    let legacy_left: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM sqlite_master WHERE name LIKE 'workflow%' \
         OR name = 'personalWorkflowRecipes' OR name = 'orchestrationDecisionGates'",
    )
    .fetch_one(store.pool())
    .await
    .unwrap();
    assert_eq!(legacy_left, 0);
    assert_eq!(schema(&store).await, fresh_schema);

    // A reopened v3 store is left alone.
    store.pool().close().await;
    drop(store);
    std::fs::remove_file(dir.path().join(RUNS_V3_BACKUP_FILE_NAME)).unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    assert!(!dir.path().join(RUNS_V3_BACKUP_FILE_NAME).exists());
    assert!(store
        .orchestration_message_by_id("q_keep")
        .await
        .unwrap()
        .is_some());
}

#[tokio::test]
async fn fresh_store_starts_at_schema_v3() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    assert_eq!(
        store.get_metadata(VERSION_KEY).await.unwrap().as_deref(),
        Some("3")
    );
    assert!(!dir.path().join(RUNS_V3_BACKUP_FILE_NAME).exists());
    let run = store
        .create_orchestration_coordinator_run("Fresh", Some("coord"), 2_000)
        .await
        .unwrap();
    let events = store.run_events(&run.id, 10).await.unwrap();
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].kind, "created");
}

#[tokio::test]
async fn unknown_schema_version_fails_closed() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    let run = store
        .create_orchestration_coordinator_run("Keep me", Some("coord"), 2_000)
        .await
        .unwrap();
    store.set_metadata(VERSION_KEY, "4").await.unwrap();
    store.pool().close().await;
    drop(store);

    let error = match RuntimeStore::open(dir.path()).await {
        Ok(_) => panic!("a store from a newer runtime must not open"),
        Err(error) => error.to_string(),
    };
    assert!(
        error.contains("unsupported orchestration schema version 4"),
        "{error}"
    );
    assert!(!dir.path().join(RUNS_V3_BACKUP_FILE_NAME).exists());

    let options = sqlx::sqlite::SqliteConnectOptions::new()
        .filename(dir.path().join(super::RUNTIME_DATABASE_FILE_NAME));
    let pool = sqlx::SqlitePool::connect_with(options).await.unwrap();
    let kept: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM orchestrationCoordinatorRuns WHERE id = ?")
            .bind(&run.id)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(kept, 1);
}

#[tokio::test]
async fn only_the_runtime_owner_resets_a_pre_v3_store() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    store.upsert_agent_profile(profile(), None).await.unwrap();
    rewind_to_v2(&store).await;
    store.pool().close().await;
    drop(store);

    let error = match RuntimeStore::open(dir.path()).await {
        Ok(_) => panic!("a CLI open must not reset a store a live host may be using"),
        Err(error) => error.to_string(),
    };
    assert!(error.contains("only the Alera runtime"), "{error}");
    assert!(!dir.path().join(RUNS_V3_BACKUP_FILE_NAME).exists());

    let store = RuntimeStore::open_read_only(dir.path()).await.unwrap();
    assert_eq!(
        store.get_metadata(VERSION_KEY).await.unwrap().as_deref(),
        Some("2")
    );
}

#[tokio::test]
async fn a_backup_left_by_an_earlier_attempt_is_kept_beside_a_fresh_one() {
    let dir = tempfile::tempdir().unwrap();
    let store = RuntimeStore::open(dir.path()).await.unwrap();
    rewind_to_v2(&store).await;
    store.pool().close().await;
    drop(store);
    let stale = dir.path().join(RUNS_V3_BACKUP_FILE_NAME);
    std::fs::write(&stale, b"stale").unwrap();

    let store = RuntimeStore::open_as_runtime_owner(dir.path())
        .await
        .unwrap();
    assert_eq!(
        store.get_metadata(VERSION_KEY).await.unwrap().as_deref(),
        Some("3")
    );
    assert_eq!(std::fs::read(&stale).unwrap(), b"stale");
    let fresh = dir.path().join("runtime-pre-runs-v3-1.sqlite");
    assert!(std::fs::metadata(&fresh).unwrap().len() > 5);
}
