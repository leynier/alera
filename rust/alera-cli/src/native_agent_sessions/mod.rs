//! Deletes the native conversations coding agents keep for a removed
//! workspace, each through the agent's own mechanism.
//!
//! Runs after the workspace removal succeeded, in a spawned task: it spawns
//! agent CLIs and walks agent stores, so it must never run on the host actor.

mod agent_command_runner;
mod agy;
mod amp;
mod claude;
mod claude_purge;
mod cleanup_context;
mod codex;
mod copilot;
mod cursor;
mod fx;
mod grok;
mod opencode;
mod pi;
mod readonly_sqlite;
mod session_id_rules;
mod storage_removal;

#[cfg(test)]
mod test_support;
#[cfg(test)]
mod tests;

use std::collections::BTreeMap;
use std::fmt;
use std::path::Path;

use alera_core::runtime::canonical_agent_type;
use futures_util::future::join_all;

use cleanup_context::CleanupContext;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NativeAgentSessionRef {
    pub agent_type: String,
    pub session_id: String,
    pub ccs_profile: Option<String>,
    pub cwd: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NativeSessionCleanupScope {
    /// Only the sessions in the plan. The checkout directory still exists.
    RegisteredSessions,
    /// The plan's sessions plus everything each agent stores for the exact
    /// workspace path, whose directory was just deleted.
    WorkspacePath,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NativeSessionCleanupPlan {
    pub workspace_path: String,
    pub scope: NativeSessionCleanupScope,
    pub sessions: Vec<NativeAgentSessionRef>,
    /// Sessions that must survive, even when a path-scope discovery finds
    /// them. Only `agent_type` and `session_id` are read.
    pub preserved: Vec<NativeAgentSessionRef>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NativeSessionCleanupOutcome {
    pub agent_type: String,
    /// The session id, or [`PATH_TARGET`] for work keyed by the workspace path.
    pub target: String,
    pub result: Result<(), String>,
}

pub const PATH_TARGET: &str = "path";

const SUPPORTED_AGENTS: [&str; 10] = [
    "claude", "codex", "opencode", "grok", "amp", "cursor", "pi", "copilot", "agy", "fx",
];

pub async fn run_native_session_cleanup(
    plan: NativeSessionCleanupPlan,
) -> Vec<NativeSessionCleanupOutcome> {
    let Some(context) = CleanupContext::resolve().await else {
        tracing::warn!("native agent session cleanup skipped: home directory is unavailable");
        return Vec::new();
    };
    run_with_context(&context, plan).await
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct RegisteredSession {
    pub id: String,
    pub ccs_profile: Option<String>,
}

struct AgentCleanupRequest {
    pub sessions: Vec<RegisteredSession>,
    /// Normalized workspace path, used for per-workspace pointers in both scopes.
    pub workspace_path: String,
    /// Exact paths to discover sessions for; `None` outside the path scope.
    pub discovery_paths: Option<Vec<String>>,
    /// Ids of this agent that no discovery may delete.
    pub preserved: Vec<String>,
}

impl AgentCleanupRequest {
    pub fn registered_ids(&self) -> impl Iterator<Item = &str> {
        self.sessions.iter().map(|session| session.id.as_str())
    }

    pub fn is_preserved(&self, id: &str) -> bool {
        self.preserved.iter().any(|preserved| preserved == id)
    }

    /// Registered ids followed by `discovered` ones, without duplicates or
    /// preserved sessions.
    pub fn ids_with(&self, discovered: impl IntoIterator<Item = String>) -> Vec<String> {
        let mut ids = self
            .registered_ids()
            .map(str::to_string)
            .collect::<Vec<_>>();
        for id in discovered {
            if !self.is_preserved(&id) && !ids.contains(&id) {
                ids.push(id);
            }
        }
        ids
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct CleanupFailure {
    /// Stable, content-free category: the only part that is logged.
    pub kind: &'static str,
    pub detail: String,
}

impl CleanupFailure {
    pub fn new(kind: &'static str, detail: impl Into<String>) -> Self {
        Self {
            kind,
            detail: detail.into(),
        }
    }

    pub fn filesystem(error: std::io::Error, path: &Path) -> Self {
        Self::new("filesystem", format!("{}: {error}", path.display()))
    }

    pub fn in_use() -> Self {
        Self::new("in_use", "session is in use by a running agent")
    }
}

impl fmt::Display for CleanupFailure {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.detail)
    }
}

struct AgentOutcome {
    pub target: String,
    pub result: Result<(), CleanupFailure>,
}

impl AgentOutcome {
    pub fn new(target: impl Into<String>, result: Result<(), CleanupFailure>) -> Self {
        Self {
            target: target.into(),
            result,
        }
    }

    pub fn path(result: Result<(), CleanupFailure>) -> Self {
        Self::new(PATH_TARGET, result)
    }
}

/// Runs blocking filesystem work off the async workers.
async fn blocking<T, F>(work: F) -> Result<T, CleanupFailure>
where
    T: Send + 'static,
    F: FnOnce() -> Result<T, CleanupFailure> + Send + 'static,
{
    tokio::task::spawn_blocking(work)
        .await
        .map_err(|error| CleanupFailure::new("task", error.to_string()))?
}

/// Keeps the first failure while still attempting every remaining target.
fn first_failure(
    results: impl IntoIterator<Item = Result<(), CleanupFailure>>,
) -> Result<(), CleanupFailure> {
    let mut kept = Ok(());
    // A plain loop rather than `try_fold`: lazy iterators passed here must
    // still run every removal after the first failure.
    for result in results {
        if kept.is_ok() {
            kept = result;
        }
    }
    kept
}

async fn run_with_context(
    context: &CleanupContext,
    plan: NativeSessionCleanupPlan,
) -> Vec<NativeSessionCleanupOutcome> {
    let workspace_path = normalize_workspace_path(&plan.workspace_path);
    let discovery_paths = match plan.scope {
        NativeSessionCleanupScope::RegisteredSessions => None,
        NativeSessionCleanupScope::WorkspacePath => {
            path_scope_paths(&workspace_path, &plan.sessions)
        }
    };
    if plan.scope == NativeSessionCleanupScope::WorkspacePath && discovery_paths.is_none() {
        tracing::warn!("native agent session cleanup ignored a non-absolute workspace path");
    }
    let mut preserved_by_agent = BTreeMap::<&str, Vec<String>>::new();
    for session in &plan.preserved {
        preserved_by_agent
            .entry(canonical_agent_type(session.agent_type.trim()))
            .or_default()
            .push(session.session_id.trim().to_string());
    }
    let mut outcomes = Vec::new();
    let mut sessions_by_agent = BTreeMap::<&'static str, Vec<RegisteredSession>>::new();
    for session in &plan.sessions {
        let agent_type = canonical_agent_type(session.agent_type.trim());
        let Some(agent) = SUPPORTED_AGENTS
            .iter()
            .copied()
            .find(|agent| *agent == agent_type)
        else {
            tracing::info!(
                agent = agent_type,
                "native agent session cleanup skipped an unsupported agent"
            );
            continue;
        };
        let preserved = preserved_by_agent
            .get(agent)
            .is_some_and(|ids| ids.iter().any(|id| id == session.session_id.trim()));
        if preserved {
            continue;
        }
        match session_id_rules::registered_session(session) {
            Ok(registered) => {
                let list = sessions_by_agent.entry(agent).or_default();
                if !list.contains(&registered) {
                    list.push(registered);
                }
            }
            Err(failure) => outcomes.push(public_outcome(
                agent,
                AgentOutcome::new(session.session_id.clone(), Err(failure)),
            )),
        }
    }
    let requests = SUPPORTED_AGENTS.iter().filter_map(|agent| {
        let sessions = sessions_by_agent.remove(agent).unwrap_or_default();
        let wants_path = discovery_paths.is_some() && *agent != "amp";
        (!sessions.is_empty() || wants_path).then(|| {
            (
                *agent,
                AgentCleanupRequest {
                    sessions,
                    workspace_path: workspace_path.clone(),
                    discovery_paths: discovery_paths.clone(),
                    preserved: preserved_by_agent.get(agent).cloned().unwrap_or_default(),
                },
            )
        })
    });
    let runs = requests.map(|(agent, request)| async move {
        let agent_outcomes = clean_agent(context, agent, &request).await;
        summarize(agent, &agent_outcomes);
        agent_outcomes
            .into_iter()
            .map(|outcome| public_outcome(agent, outcome))
            .collect::<Vec<_>>()
    });
    for agent_outcomes in join_all(runs).await {
        outcomes.extend(agent_outcomes);
    }
    outcomes
}

async fn clean_agent(
    context: &CleanupContext,
    agent: &'static str,
    request: &AgentCleanupRequest,
) -> Vec<AgentOutcome> {
    match agent {
        "claude" => claude::clean(context, request).await,
        "codex" => codex::clean(context, request).await,
        "opencode" => opencode::clean(context, request).await,
        "grok" => grok::clean(context, request).await,
        "amp" => amp::clean(context, request).await,
        "cursor" => cursor::clean(context, request).await,
        "pi" => pi::clean(context, request).await,
        "copilot" => copilot::clean(context, request).await,
        "agy" => agy::clean(context, request).await,
        "fx" => fx::clean(context, request).await,
        _ => Vec::new(),
    }
}

fn summarize(agent: &str, outcomes: &[AgentOutcome]) {
    let failed = outcomes
        .iter()
        .filter(|outcome| outcome.result.is_err())
        .count();
    for outcome in outcomes {
        if let Err(failure) = &outcome.result {
            tracing::warn!(
                agent,
                target = %outcome.target,
                kind = failure.kind,
                "native agent session cleanup failed for a target"
            );
        }
    }
    tracing::info!(
        agent,
        succeeded = outcomes.len() - failed,
        failed,
        "native agent session cleanup finished"
    );
}

fn public_outcome(agent: &str, outcome: AgentOutcome) -> NativeSessionCleanupOutcome {
    NativeSessionCleanupOutcome {
        agent_type: agent.to_string(),
        target: outcome.target,
        result: outcome.result.map_err(|failure| failure.detail),
    }
}

fn normalize_workspace_path(path: &str) -> String {
    let trimmed = path.trim();
    let without_separator = trimmed.trim_end_matches(['/', '\\']);
    if without_separator.is_empty() || without_separator.ends_with(':') {
        // `/` or `C:\` stays a root rather than collapsing to "" or a drive-relative path.
        return trimmed.to_string();
    }
    without_separator.to_string()
}

/// The workspace path plus registered session directories inside it, so an
/// agent started in a subdirectory of the removed worktree is matched too.
fn path_scope_paths(
    workspace_path: &str,
    sessions: &[NativeAgentSessionRef],
) -> Option<Vec<String>> {
    let root = Path::new(workspace_path);
    if !root.is_absolute() || root.parent().is_none() {
        return None;
    }
    let mut paths = vec![workspace_path.to_string()];
    for cwd in sessions.iter().filter_map(|session| session.cwd.as_deref()) {
        let cwd = normalize_workspace_path(cwd);
        if Path::new(&cwd).starts_with(root) && !paths.contains(&cwd) {
            paths.push(cwd);
        }
    }
    Some(paths)
}
