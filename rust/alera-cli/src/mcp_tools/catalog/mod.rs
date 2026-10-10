//! The tool catalog, one module per domain. The constructors here set each
//! access class and its default timeout; every domain module lists its tools
//! in the order clients see them.

mod agent_skills;
mod agents;
mod agents_manage;
mod automations;
mod automations_manage;
mod events;
mod inbox;
mod inbox_manage;
mod orchestration;
mod orchestration_manage;
mod projects;
mod projects_manage;
mod prompt_workspace;
mod pull_requests;
mod runtime;
mod runtime_manage;
mod terminals;
mod terminals_manage;
mod workflows;
mod workspaces;
mod workspaces_manage;

use serde_json::Value;

use super::schema::{integer, object, string};
use super::{Invocation, ToolAccess, ToolArguments, ToolInputError, ToolSpec, MAX_WAIT_SECONDS};

/// Inbox used for questions an MCP client asks, kept apart from the user's own.
pub(super) const MCP_INBOX: &str = "ext:mcp";
pub(super) const LIST_TIMEOUT: u64 = 30;
pub(super) const MUTATION_TIMEOUT: u64 = 30;
/// A wait or launch runs up to [`MAX_WAIT_SECONDS`] plus process start-up.
pub(super) const WAIT_TIMEOUT: u64 = MAX_WAIT_SECONDS + 8;
pub(super) const LAUNCH_TIMEOUT: u64 = MAX_WAIT_SECONDS + 8;
pub(super) const PROMPT_LIMIT: u64 = 65_536;

type Build = fn(&ToolArguments) -> Result<Invocation, ToolInputError>;

fn spec(
    access: ToolAccess,
    timeout_seconds: u64,
    name: &'static str,
    title: &'static str,
    description: &'static str,
    input_schema: fn() -> Value,
    build: Build,
) -> ToolSpec {
    ToolSpec {
        name,
        title,
        description,
        access,
        timeout_seconds,
        destructive: false,
        idempotent: false,
        client_request_flag: None,
        omit_fields: &[],
        input_schema,
        build,
    }
}

/// A tool that only reads runtime state.
pub(super) fn read(
    name: &'static str,
    title: &'static str,
    description: &'static str,
    input_schema: fn() -> Value,
    build: Build,
) -> ToolSpec {
    spec(
        ToolAccess::Read,
        LIST_TIMEOUT,
        name,
        title,
        description,
        input_schema,
        build,
    )
}

/// A tool that changes workspaces, agents, terminals, or messages.
pub(super) fn execute(
    name: &'static str,
    title: &'static str,
    description: &'static str,
    input_schema: fn() -> Value,
    build: Build,
) -> ToolSpec {
    spec(
        ToolAccess::Execute,
        MUTATION_TIMEOUT,
        name,
        title,
        description,
        input_schema,
        build,
    )
}

/// A tool reserved for runtime administration, agent configuration, and
/// internal maintenance. It needs the `mcp:admin` scope and the `admin` level.
pub(super) fn admin(
    name: &'static str,
    title: &'static str,
    description: &'static str,
    input_schema: fn() -> Value,
    build: Build,
) -> ToolSpec {
    spec(
        ToolAccess::Admin,
        MUTATION_TIMEOUT,
        name,
        title,
        description,
        input_schema,
        build,
    )
}

pub(super) fn tools() -> Vec<ToolSpec> {
    let groups: [fn() -> Vec<ToolSpec>; 21] = [
        runtime::tools,
        runtime_manage::tools,
        projects::tools,
        projects_manage::tools,
        workspaces::tools,
        prompt_workspace::tools,
        workspaces_manage::tools,
        terminals::tools,
        terminals_manage::tools,
        agents::tools,
        agents_manage::tools,
        inbox::tools,
        inbox_manage::tools,
        orchestration::tools,
        orchestration_manage::tools,
        workflows::tools,
        automations::tools,
        automations_manage::tools,
        pull_requests::tools,
        events::tools,
        agent_skills::tools,
    ];
    groups.iter().flat_map(|group| group()).collect()
}

pub(super) fn no_arguments() -> Value {
    object(&[], &[])
}

pub(super) fn wait_seconds(arguments: &ToolArguments, default: u64) -> u64 {
    arguments
        .integer("timeoutSeconds")
        .unwrap_or(default)
        .clamp(1, MAX_WAIT_SECONDS)
}

pub(super) fn wait_schema() -> Value {
    integer(
        "Seconds to wait before returning the current state. Call again to keep waiting.",
        1,
        MAX_WAIT_SECONDS,
    )
}

/// Profiles are addressed by stable id (`prof_...`) or by unique name.
pub(super) fn with_profile(invocation: Invocation, profile: String) -> Invocation {
    if profile.starts_with("prof_") {
        invocation.option("--profile-id", profile)
    } else {
        invocation.option("--profile-name", profile)
    }
}

pub(super) fn profile_schema() -> Value {
    string("Agent profile id or unique name from list_agent_profiles.")
}
