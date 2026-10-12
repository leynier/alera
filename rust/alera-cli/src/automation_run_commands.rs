//! Automation commands an operator outside the run uses: clone, take over,
//! and run lifecycle calls bound to the identity the run recorded.

use anyhow::{anyhow, bail, Result};
use serde_json::{json, Map, Value};

use super::{AutomationTargetArgs, RuntimeDirArgs};
use crate::cli::{AutomationCloneArgs, AutomationTakeOverArgs};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::RUNTIME_HOST_AUTOMATION_TERMINAL_OBSERVE_CAPABILITY;

/// Fields of a saved automation that belong to that one record, so a copy
/// gets its own.
const RECORD_FIELDS: &[&str] = &[
    "id",
    "slug",
    "state",
    "revision",
    "approvedRevision",
    "createdBy",
    "modifiedBy",
    "createdAt",
    "updatedAt",
    "creationRequestKey",
    "creationRequestFingerprint",
    "scheduleCursorAt",
    "stateBeforeTrash",
    "circuitOpened",
    "circuitOpenedAt",
    "tagIds",
];

/// The target identity for a run lifecycle call. With `use_run_identity` it
/// is the identity the run recorded, which is what the Alera app sends;
/// explicit selectors still win.
pub(super) async fn identity(
    runtime: &RuntimeDirArgs,
    run_id: &str,
    target: &AutomationTargetArgs,
    use_run_identity: bool,
) -> Result<Value> {
    if !use_run_identity {
        return Ok(super::target_identity(target));
    }
    let shown = super::request(runtime, "automation.runShow", json!({"id": run_id})).await?;
    recorded_identity(&shown["run"], target)
}

fn recorded_identity(run: &Value, target: &AutomationTargetArgs) -> Result<Value> {
    let mut identity = run["targetIdentity"]
        .as_object()
        .cloned()
        .filter(|identity| identity.values().any(|value| !value.is_null()))
        .ok_or_else(|| anyhow!("automation run has no recorded target identity yet"))?;
    let explicit = [
        ("attemptId", &target.attempt_id),
        ("workspaceId", &target.workspace_id),
        ("tabId", &target.tab_id),
        ("sessionId", &target.session_id),
        ("profileId", &target.profile_id),
        ("conversationId", &target.conversation_id),
        ("terminalHandle", &target.terminal_handle),
    ];
    if let Some(attempt) = run["attemptId"].as_str() {
        identity.insert("attemptId".into(), json!(attempt));
    }
    for (key, value) in explicit {
        if let Some(value) = value.as_ref().filter(|value| !value.trim().is_empty()) {
            identity.insert(key.into(), json!(value));
        }
    }
    Ok(Value::Object(identity))
}

/// Creates a new automation with the settings and target of an existing
/// one, named "<name> Copy" unless a name is given.
pub(super) async fn clone(runtime: &RuntimeDirArgs, args: AutomationCloneArgs) -> Result<Value> {
    let shown = super::request(runtime, "automation.show", json!({"id": args.id})).await?;
    let definition = copy_definition(&shown["automation"], args.name, args.draft)?;
    let mut payload = json!({"automation": definition, "requestKey": args.request_key});
    super::add_automation_context(&mut payload);
    super::request(runtime, "automation.create", payload).await
}

fn copy_definition(saved: &Value, name: Option<String>, draft: bool) -> Result<Value> {
    let Some(saved) = saved.as_object() else {
        bail!("automation definition is missing");
    };
    let mut copy: Map<String, Value> = saved
        .iter()
        .filter(|(key, _)| !RECORD_FIELDS.contains(&key.as_str()))
        .map(|(key, value)| (key.clone(), value.clone()))
        .collect();
    let name =
        name.unwrap_or_else(|| format!("{} Copy", saved["name"].as_str().unwrap_or("Automation")));
    copy.insert("name".into(), json!(name));
    if draft {
        copy.insert("state".into(), json!("draft"));
    }
    Ok(Value::Object(copy))
}

pub(super) async fn take_over(
    runtime: &RuntimeDirArgs,
    args: AutomationTakeOverArgs,
) -> Result<Value> {
    let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
        &crate::runtime_dir(runtime),
        RUNTIME_HOST_AUTOMATION_TERMINAL_OBSERVE_CAPABILITY,
    )
    .await?;
    client
        .request_value("automation.takeOver", &json!({"runId": args.run_id}))
        .await
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::{copy_definition, recorded_identity, AutomationTargetArgs};

    #[test]
    fn a_copy_drops_record_fields_and_takes_a_new_name() {
        let saved = json!({
            "id": "a1", "slug": "nightly-a1", "name": "Nightly", "state": "archived",
            "revision": 4, "promptTemplate": "Run", "schedule": {"recurring": {}},
            "creationRequestKey": "key", "tagIds": ["t1"],
        });
        let copy = copy_definition(&saved, None, false).unwrap();
        assert_eq!(copy["name"], "Nightly Copy");
        assert_eq!(copy["promptTemplate"], "Run");
        for field in [
            "id",
            "slug",
            "state",
            "revision",
            "creationRequestKey",
            "tagIds",
        ] {
            assert!(copy.get(field).is_none(), "{field} was copied");
        }
        let draft = copy_definition(&saved, Some("Other".into()), true).unwrap();
        assert_eq!(draft["name"], "Other");
        assert_eq!(draft["state"], "draft");
        assert!(copy_definition(&json!(null), None, false).is_err());
    }

    #[test]
    fn the_recorded_identity_carries_the_attempt_and_explicit_overrides() {
        let run = json!({
            "attemptId": "attempt-2",
            "targetIdentity": {"workspaceId": "w", "tabId": "t", "terminalHandle": "s"},
        });
        let identity = recorded_identity(
            &run,
            &AutomationTargetArgs {
                tab_id: Some("explicit".into()),
                ..AutomationTargetArgs::default()
            },
        )
        .unwrap();
        assert_eq!(identity["attemptId"], "attempt-2");
        assert_eq!(identity["workspaceId"], "w");
        assert_eq!(identity["tabId"], "explicit");
        assert!(recorded_identity(&json!({"targetIdentity": null}), &Default::default()).is_err());
        assert!(recorded_identity(
            &json!({"targetIdentity": {"tabId": null}}),
            &Default::default()
        )
        .is_err());
    }
}
