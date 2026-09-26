//! What a satellite may ask its hub, and how the hub shapes the question.
//!
//! One table serves both ends. The satellite forwards a verb from its own CLI
//! only when the table admits it, and the hub refuses anything else even when
//! a satellite sends it anyway, because a host reached over ssh is less trusted
//! than the desktop. The table is default deny: a verb the hub grows later is
//! not forwarded until someone adds it here on purpose.

use std::time::Duration;

use serde_json::{json, Value};

/// Verb classes a remote host may never drive on the desktop. Listed even
/// where the default already denies them, so a later allowed prefix cannot
/// swallow them by accident. Terminal and session verbs would let a
/// compromised server type into the user's terminals; the rest configure the
/// desktop itself, name local folders, or hold credentials.
const DENIED_PREFIXES: &[&str] = &[
    "terminal.",
    "hub.",
    "hostLink.",
    "sshTarget.",
    "account.",
    "configuration.",
    "runtimeSettings.",
    "runtimeMetadata.",
    "mobile.",
    "aiDictation.",
    "aiText.",
    "aiAssist.",
    "automation.",
    "shellEnvironment.",
    "hostDirectory.",
    "host.",
    "project.clone.",
    "workspace.files.",
    "git.",
    "agentQuota.",
    "agentSkill.",
    "cliRegistration.",
    "codex.",
    "checkout.",
    "tab.",
    "layout.",
    "workbenchViewPrefs.",
    "pairing.",
    "resources.",
];

/// Exact verbs denied under otherwise allowed prefixes, plus the bare session
/// verbs. `project.register` names a folder on the hub's disk. `status.get`
/// describes the runtime that answers it, and `runtime-attach` asks it before
/// registering as the hub link, so forwarding it would hand the hub's status
/// to the attach event. The `workspace.*` entries are what the owner commands
/// (`remote_owner_*`, the Setup tab) send to the satellite about its own
/// checkout and sessions, and MUST keep running where the checkout is.
const DENIED_VERBS: &[&str] = &[
    "hello",
    "configure",
    "createOrAttach",
    "write",
    "terminate",
    "resize",
    "detach",
    "restored",
    "status.get",
    "project.register",
    "workspace.runSetup",
    "workspace.prepareRelocationSetup",
    "workspace.recoverRelocationSetup",
    "workspace.cancelRelocationSetup",
    "workspace.retirementReceipt",
    "workspace.sshRelocationRecovery",
    "workspace.relocationRecovery",
];

/// Hub-owned records and the actions on them. `workspace.bufferGuard.*` is
/// included on purpose: the guard is about editor buffers open in the desktop
/// app, not PTY sessions, and `workspace remove` cannot complete without one.
const ALLOWED_PREFIXES: &[&str] = &[
    "project.",
    "workspace.",
    "workspaceTag.",
    "workspaceSection.",
    "workspaceRelation.",
    "workspaceCascade.",
    "workspaceActivity.",
    "projectConfig.",
    "agentProfile.",
    "orchestration.",
    "issue.",
    "linkedIssue.",
    "linkedReview.",
    "pullRequestWatch.",
];

const ALLOWED_VERBS: &[&str] = &["agentPresence.list"];

/// Verbs whose `hostId` names where the checkout lives. A user typing in a
/// terminal on host X means host X, so an absent `hostId` becomes the origin.
const HOST_DEFAULTED_VERBS: &[&str] = &[
    "workspace.createShared",
    "workspace.createManaged",
    "project.hosts.add",
    "project.registerRemote",
    "project.checkout.register",
];

/// Verbs that may clone a repository or create a worktree on another host.
const PROVISIONING_VERBS: &[&str] = &[
    "workspace.createShared",
    "workspace.createManaged",
    "project.hosts.add",
    "project.registerRemote",
];

/// `hostId: "origin"` in a forwarded payload means the host the CLI runs on.
pub(super) const ORIGIN_HOST_ALIAS: &str = "origin";

const DEFAULT_REPLY_DEADLINE: Duration = Duration::from_secs(60);
const REMOVAL_REPLY_DEADLINE: Duration = Duration::from_secs(5 * 60);
const PROVISIONING_REPLY_DEADLINE: Duration = Duration::from_secs(30 * 60);
/// A long poll owes its reply a little after its own wait ends.
const WAIT_REPLY_GRACE: Duration = Duration::from_secs(30);

/// Whether the hub answers `request_type` for a satellite.
pub(super) fn hub_answers(request_type: &str) -> bool {
    if DENIED_VERBS.contains(&request_type)
        || DENIED_PREFIXES
            .iter()
            .any(|prefix| request_type.starts_with(prefix))
    {
        return false;
    }
    ALLOWED_VERBS.contains(&request_type)
        || ALLOWED_PREFIXES
            .iter()
            .any(|prefix| request_type.starts_with(prefix))
}

pub(super) fn refusal(request_type: &str) -> crate::terminal_host::host_error::HostError {
    crate::terminal_host::host_error::HostError::state(format!(
        "A remote host cannot ask the Alera desktop for {request_type}. Run this command on the desktop instead."
    ))
}

/// Who is asking, as seen by the satellite.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct ForwardingContext {
    /// This runtime has mirrored a hub workspace.
    pub satellite: bool,
    pub authenticated: bool,
    /// A local socket client, never a paired phone.
    pub local_client: bool,
    /// The client registered itself as the hub's link: its requests come
    /// from the hub and are handled here.
    pub hub_link: bool,
}

/// Whether a satellite forwards `request_type` to its hub instead of handling
/// it against its own copies.
pub(super) fn forwards_to_hub(context: ForwardingContext, request_type: &str) -> bool {
    context.satellite
        && context.authenticated
        && context.local_client
        && !context.hub_link
        && hub_answers(request_type)
}

/// Owner-side work the hub itself started on this host over ssh. Retiring a
/// mirrored copy (`alera project retire-owner-workspace`) names the exact
/// instance it was told to retire in `expectedInstanceId`, and a buffer guard
/// acquired here is inspected and released here. The CLI's own `workspace
/// remove` names only an id, so its removals still travel to the hub.
pub(super) fn stays_with_owner(request_type: &str, payload: &Value, guard_is_local: bool) -> bool {
    match request_type {
        "workspace.bufferGuard.acquire" | "workspace.removeShared" | "workspace.removeManaged" => {
            optional_string(payload, "expectedInstanceId").is_some()
        }
        "workspace.bufferGuard.status"
        | "workspace.bufferGuard.release"
        | "workspace.bufferGuard.ack" => guard_is_local,
        _ => false,
    }
}

/// Stamps the origin on a forwarded payload: `originHostId` for handlers that
/// care where the question came from, `hostId: "origin"` resolved, and the
/// origin as the default host for verbs that place a checkout.
pub(super) fn apply_origin(request_type: &str, payload: Value, origin_host_id: &str) -> Value {
    let mut payload = match payload {
        Value::Object(map) => map,
        _ => serde_json::Map::new(),
    };
    payload.insert("originHostId".into(), json!(origin_host_id));
    let host_id = payload.get("hostId");
    let named_origin = host_id.and_then(Value::as_str) == Some(ORIGIN_HOST_ALIAS);
    let absent = match host_id {
        None | Some(Value::Null) => true,
        Some(Value::String(value)) => value.trim().is_empty(),
        Some(_) => false,
    };
    if named_origin || (absent && HOST_DEFAULTED_VERBS.contains(&request_type)) {
        payload.insert("hostId".into(), json!(origin_host_id));
    }
    Value::Object(payload)
}

/// How long the hub has to answer, and how long the satellite waits for it.
/// The payload's own `timeoutMs` (orchestration waits) extends the default.
pub(super) fn reply_deadline(request_type: &str, payload: &Value) -> Duration {
    if PROVISIONING_VERBS.contains(&request_type) {
        return PROVISIONING_REPLY_DEADLINE;
    }
    if request_type.starts_with("workspace.remove") {
        return REMOVAL_REPLY_DEADLINE;
    }
    if let Some(timeout_ms) = payload.get("timeoutMs").and_then(Value::as_u64) {
        return Duration::from_millis(timeout_ms)
            .saturating_add(WAIT_REPLY_GRACE)
            .clamp(DEFAULT_REPLY_DEADLINE, PROVISIONING_REPLY_DEADLINE);
    }
    DEFAULT_REPLY_DEADLINE
}

/// The hub verb that answers a CLI listing. `workspace.list` without a project
/// is the hub's `workspace.listAll`; everything else is sent as it came.
pub(super) fn listing_request(request_type: &str, payload: &Value) -> (String, Value) {
    if request_type == "workspace.list" && optional_string(payload, "projectId").is_none() {
        return ("workspace.listAll".into(), json!({}));
    }
    (request_type.to_string(), payload.clone())
}

/// The CLI listings keep the `{items, originHostId}` shape the satellite CLI
/// prints, with `workspace.list` filtered by the (already resolved) `hostId`.
pub(super) fn listing_answer(
    request_type: &str,
    payload: &Value,
    origin_host_id: &str,
    answer: Value,
) -> Value {
    match request_type {
        "project.list" => json!({"items": answer, "originHostId": origin_host_id}),
        "workspace.list" => {
            let mut items = answer;
            if let Some(host_id) = optional_string(payload, "hostId") {
                let host_id = crate::ssh_remote::normalized_host_id(Some(&host_id));
                if let Some(workspaces) = items.as_array_mut() {
                    workspaces.retain(|workspace| {
                        workspace.get("hostId").and_then(Value::as_str) == Some(host_id.as_str())
                    });
                }
            }
            json!({"items": items, "originHostId": origin_host_id})
        }
        _ => answer,
    }
}

fn optional_string(payload: &Value, key: &str) -> Option<String> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

#[cfg(test)]
#[path = "hub_reverse_policy_tests.rs"]
mod tests;
