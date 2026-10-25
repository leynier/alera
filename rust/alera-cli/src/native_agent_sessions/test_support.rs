use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use sqlx::sqlite::SqliteConnectOptions;
use sqlx::{ConnectOptions, Connection};

use super::cleanup_context::{AgentCommandRunner, CleanupContext};
use super::{
    run_with_context, NativeAgentSessionRef, NativeSessionCleanupOutcome, NativeSessionCleanupPlan,
    NativeSessionCleanupScope,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct RecordedCommand {
    pub program: String,
    pub args: Vec<String>,
    pub env: BTreeMap<String, String>,
}

/// Records every command instead of spawning it; a command whose argv
/// contains a `failing` value reports a non-zero exit.
#[derive(Default)]
pub(super) struct FakeRunner {
    pub commands: Mutex<Vec<RecordedCommand>>,
    pub failing: Mutex<Vec<String>>,
}

#[async_trait]
impl AgentCommandRunner for FakeRunner {
    async fn run(
        &self,
        program: &str,
        args: &[String],
        env: &BTreeMap<String, String>,
    ) -> Result<(), String> {
        self.commands.lock().unwrap().push(RecordedCommand {
            program: program.to_string(),
            args: args.to_vec(),
            env: env.clone(),
        });
        let failing = self.failing.lock().unwrap();
        if args.iter().any(|arg| failing.contains(arg)) {
            return Err(format!("{program} exited with 1"));
        }
        Ok(())
    }
}

pub(super) struct Fixture {
    pub temp: tempfile::TempDir,
    pub runner: Arc<FakeRunner>,
    pub variables: BTreeMap<String, String>,
    pub process_alive: fn(u32) -> bool,
}

impl Fixture {
    pub fn new() -> Self {
        Self {
            temp: tempfile::tempdir().unwrap(),
            runner: Arc::new(FakeRunner::default()),
            variables: BTreeMap::new(),
            process_alive: |_| false,
        }
    }

    pub fn home(&self) -> PathBuf {
        self.temp.path().join("home")
    }

    pub fn context(&self) -> CleanupContext {
        std::fs::create_dir_all(self.home()).unwrap();
        CleanupContext::new(
            self.home(),
            self.variables.clone(),
            self.runner.clone(),
            self.process_alive,
        )
    }

    pub fn commands(&self) -> Vec<RecordedCommand> {
        self.runner.commands.lock().unwrap().clone()
    }

    pub fn argv(&self) -> Vec<String> {
        self.commands()
            .into_iter()
            .map(|command| format!("{} {}", command.program, command.args.join(" ")))
            .collect()
    }

    pub fn fail_on(&self, arg: &str) {
        self.runner.failing.lock().unwrap().push(arg.to_string());
    }

    pub async fn run(
        &self,
        scope: NativeSessionCleanupScope,
        workspace_path: &str,
        sessions: Vec<NativeAgentSessionRef>,
    ) -> Vec<NativeSessionCleanupOutcome> {
        self.run_preserving(scope, workspace_path, sessions, Vec::new())
            .await
    }

    pub async fn run_preserving(
        &self,
        scope: NativeSessionCleanupScope,
        workspace_path: &str,
        sessions: Vec<NativeAgentSessionRef>,
        preserved: Vec<NativeAgentSessionRef>,
    ) -> Vec<NativeSessionCleanupOutcome> {
        let plan = NativeSessionCleanupPlan {
            workspace_path: workspace_path.to_string(),
            scope,
            sessions,
            preserved,
        };
        run_with_context(&self.context(), plan).await
    }
}

pub(super) fn session(agent_type: &str, session_id: &str) -> NativeAgentSessionRef {
    NativeAgentSessionRef {
        agent_type: agent_type.to_string(),
        session_id: session_id.to_string(),
        ccs_profile: None,
        cwd: None,
    }
}

pub(super) fn write(path: &Path, contents: &str) {
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, contents).unwrap();
}

pub(super) fn outcome_for<'a>(
    outcomes: &'a [NativeSessionCleanupOutcome],
    agent: &str,
    target: &str,
) -> &'a NativeSessionCleanupOutcome {
    outcomes
        .iter()
        .find(|outcome| outcome.agent_type == agent && outcome.target == target)
        .unwrap_or_else(|| panic!("no outcome for {agent} {target}: {outcomes:?}"))
}

/// Creates a writable SQLite fixture and runs `statements` against it.
pub(super) async fn sqlite_fixture(path: &Path, statements: &[&str]) {
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    let mut connection = SqliteConnectOptions::new()
        .filename(path)
        .create_if_missing(true)
        .connect()
        .await
        .unwrap();
    for statement in statements {
        sqlx::query(sqlx::AssertSqlSafe(statement.to_string()))
            .execute(&mut connection)
            .await
            .unwrap();
    }
    connection.close().await.unwrap();
}
