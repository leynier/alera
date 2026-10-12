use super::{AutomationDefinitionFileArgs, RuntimeDirArgs};
use crate::terminal_host::protocol::RUNTIME_HOST_AUTOMATION_REUSE_CAPABILITY;
use anyhow::{bail, Result};
use serde_json::{json, Value};

pub(super) async fn author(
    runtime: &RuntimeDirArgs,
    args: AutomationDefinitionFileArgs,
    verb: &str,
) -> Result<Value> {
    let mut definition = match args.file.as_deref() {
        Some(path) => super::read_json(path)?,
        None => json!({}),
    };
    if !definition.is_object() {
        bail!("Automation input must be a JSON object");
    }
    if let Some(name) = args.name {
        definition["name"] = json!(name);
    }
    if let Some(prompt) = args.prompt {
        definition["promptTemplate"] = json!(prompt);
    }
    if let Some(path) = args.prompt_file {
        definition["promptTemplate"] = json!(std::fs::read_to_string(path)?);
    }
    let timezone = args.timezone.unwrap_or_else(|| "UTC".into());
    if let Some(cron) = args.cron {
        definition["schedule"] = json!({"recurring":{"cron":cron,"timezone":timezone}});
    }
    if let Some(at) = args.at {
        definition["schedule"] = json!({"oneTime":{"at":at,"timezone":timezone}});
    }
    if args.draft {
        definition["state"] = json!("draft");
    }
    let reuse = args.reuse.as_deref().map(reuse_policy);
    if let Some(policy) = reuse {
        definition["reusePolicy"] = json!(policy);
    }
    let from_env = |value: Option<String>, key: &str| {
        value
            .or_else(|| std::env::var(key).ok())
            .filter(|v| !v.trim().is_empty())
    };
    let explicit_workspace = args.workspace_id.clone();
    let workspace = from_env(args.workspace_id, "ALERA_WORKSPACE_ID");
    let profile = from_env(args.profile_id, "ALERA_AGENT_PROFILE_ID");
    if let Some(target) = args.target.as_deref() {
        let required = |value: Option<String>, label: &str| {
            value.ok_or_else(|| anyhow::anyhow!("{label} is required for {target}"))
        };
        definition["target"] = match target {
            "fresh-tab" => {
                json!({"freshTab":{"workspaceId":required(workspace,"--workspace-id")?,"agentProfileId":required(profile,"--profile-id")?}})
            }
            "existing-tab" => {
                json!({"existingTab":{"workspaceId":required(workspace,"--workspace-id")?,"tabId":required(from_env(args.tab_id,"ALERA_TAB_ID"),"--tab-id")?,"conversationId":required(from_env(args.conversation_id,"ALERA_AGENT_CONVERSATION_ID"),"--conversation-id")?}})
            }
            "worktree" | "managed-workspace" | "project-worktree" => {
                let (project_id, parent_workspace_id) = match target {
                    "managed-workspace" => (None, Some(required(workspace, "--workspace-id")?)),
                    "project-worktree" => (
                        Some(required(args.project_id.clone(), "--project-id")?),
                        None,
                    ),
                    // A parent workspace is only implied by the terminal's
                    // workspace when no project was named.
                    _ => match args.project_id.clone() {
                        Some(project_id) => (Some(project_id), explicit_workspace),
                        None => (
                            None,
                            Some(required(workspace, "--project-id or --workspace-id")?),
                        ),
                    },
                };
                let mut worktree = json!({
                    "sourceBranch": required(args.source_branch, "--source-branch")?,
                    "agentProfileId": required(profile, "--profile-id")?,
                });
                if let Some(project_id) = project_id {
                    definition["projectId"] = json!(project_id);
                    worktree["projectId"] = json!(project_id);
                }
                if let Some(parent) = parent_workspace_id {
                    worktree["parentWorkspaceId"] = json!(parent);
                }
                json!({ "worktree": worktree })
            }
            "project-checkout" => {
                json!({"projectCheckout":{"projectId":required(args.project_id,"--project-id")?,"hostId":required(args.host_id,"--host-id")?,"agentProfileId":required(profile,"--profile-id")?}})
            }
            _ => bail!("Unknown target"),
        };
    }
    if let Some(origin) = if verb == "automation.patch" {
        args.origin_workspace_id
    } else {
        from_env(args.origin_workspace_id, "ALERA_WORKSPACE_ID")
    } {
        definition["originWorkspaceId"] = json!(origin);
    }
    let mut payload = if verb == "automation.patch" {
        let id = args
            .id
            .or_else(|| definition["id"].as_str().map(str::to_string))
            .ok_or_else(|| anyhow::anyhow!("Edit requires --id or id in the JSON file"))?;
        if args.dry_run {
            let saved = super::request(runtime, "automation.show", json!({"id":id})).await?;
            let mut combined = saved["automation"].clone();
            for (key, value) in definition.as_object().expect("checked object") {
                combined[key] = value.clone();
            }
            definition = combined;
            json!({"automation":definition})
        } else {
            json!({"id":id,"changes":definition,"expectedRevision":args.expected_revision})
        }
    } else if verb == "automation.previewSchedule" {
        let schedule = definition
            .get("schedule")
            .cloned()
            .unwrap_or(definition.clone());
        json!({"schedule":schedule,"count":5})
    } else {
        json!({"automation":definition,"requestKey":args.request_key})
    };
    super::add_automation_context(&mut payload);
    if let Ok(handle) = std::env::var("ALERA_TERMINAL_HANDLE") {
        payload["terminalHandle"] = json!(handle);
    }
    let verb = if args.dry_run {
        "automation.readiness"
    } else {
        verb
    };
    // An older host would silently drop the policy, so refuse instead.
    if reuse.is_some() {
        return super::request_requiring(
            runtime,
            verb,
            payload,
            RUNTIME_HOST_AUTOMATION_REUSE_CAPABILITY,
        )
        .await;
    }
    super::request(runtime, verb, payload).await
}

fn reuse_policy(flag: &str) -> &'static str {
    match flag {
        "workspace" => "reuseWorkspace",
        "conversation" => "reuseConversation",
        _ => "newEachRun",
    }
}

#[cfg(test)]
mod tests {
    use clap::Parser;

    #[test]
    fn reuse_flag_maps_to_the_definition_policy() {
        assert_eq!(super::reuse_policy("none"), "newEachRun");
        assert_eq!(super::reuse_policy("workspace"), "reuseWorkspace");
        assert_eq!(super::reuse_policy("conversation"), "reuseConversation");
        for args in [
            vec!["alera", "automation", "create", "--reuse", "conversation"],
            vec![
                "alera",
                "automation",
                "edit",
                "--id",
                "a",
                "--reuse",
                "none",
            ],
            vec![
                "alera",
                "automation",
                "unbind",
                "--id",
                "a",
                "--reason",
                "why",
            ],
        ] {
            assert!(crate::cli::Cli::try_parse_from(&args).is_ok(), "{args:?}");
        }
        assert!(crate::cli::Cli::try_parse_from([
            "alera",
            "automation",
            "create",
            "--reuse",
            "tab"
        ])
        .is_err());
    }
}
