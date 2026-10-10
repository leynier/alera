//! Runtime settings, integrations, quotas, resources, and voice.

use serde_json::Value;

use super::{admin, execute, no_arguments, read, WAIT_TIMEOUT};
use crate::mcp_tools::schema::{boolean, integer, object, one_of, string, string_list, text};
use crate::mcp_tools::{Invocation, ToolArguments, ToolInputError, ToolSpec};
use crate::runtime_settings_commands::selectable_ai_assist_agents;

/// Each `update_runtime_settings` property and the `runtime settings set`
/// key it writes. The CLI holds the allowlist and checks every value.
const SETTING_PROPERTIES: &[(&str, &str)] = &[
    ("workspaceDirectory", "workspaceDirectory"),
    ("confirmProjectRemoval", "confirmProjectRemoval"),
    ("confirmWorkspaceRemoval", "confirmWorkspaceRemoval"),
    ("defaultAgentProfileId", "defaultAgentProfileId"),
    ("aiAssistEnabled", "aiAssist.enabled"),
    (
        "aiAssistAutoGenerateAgentTitles",
        "aiAssist.autoGenerateAgentTitles",
    ),
    ("aiAssistAgent", "aiAssist.agent"),
    ("aiAssistTimeoutSeconds", "aiAssist.timeoutSeconds"),
    ("automationStartAtLogin", "automation.startAtLogin"),
    ("automationRunRetentionDays", "automation.runRetentionDays"),
    (
        "automationAuditRetentionDays",
        "automation.auditRetentionDays",
    ),
    (
        "automationTrashRetentionDays",
        "automation.trashRetentionDays",
    ),
];

/// Agent integration keys `runtime agents enable` accepts.
const INTEGRATION_AGENTS: &[&str] = &[
    "codex",
    "claude",
    "copilot",
    "cursor",
    "agy",
    "opencode",
    "opencode2",
    "pi",
    "amp",
    "grok",
    "fx",
];

/// `runtime agents enable` prints every runtime setting when a host is
/// running. Only the integration switches belong in this tool's result.
const SETTINGS_OUTSIDE_INTEGRATIONS: &[&str] = &[
    "workspaceDirectory",
    "confirmProjectRemoval",
    "confirmWorkspaceRemoval",
    "defaultAgentProfileId",
    "agentQuotas",
    "mobilePushNotifications",
    "aiTextGeneration",
    "textActions",
    "automation",
    "voice",
];

fn settings_schema() -> Value {
    let agents = selectable_ai_assist_agents();
    let retention = || integer("Days to keep, from 1 to 3650.", 1, 3650);
    object(
        &[
            (
                "workspaceDirectory",
                string("Folder where new worktrees are created."),
            ),
            (
                "confirmProjectRemoval",
                boolean("Ask before removing a project in the app."),
            ),
            (
                "confirmWorkspaceRemoval",
                boolean("Ask before removing a workspace in the app."),
            ),
            (
                "defaultAgentProfileId",
                string("Profile id used when a prompt names none."),
            ),
            ("aiAssistEnabled", boolean("Turn AI Assist on or off.")),
            (
                "aiAssistAutoGenerateAgentTitles",
                boolean("Name agent tabs from their conversations."),
            ),
            ("aiAssistAgent", one_of("Agent AI Assist runs.", &agents)),
            (
                "aiAssistTimeoutSeconds",
                integer("AI Assist time limit in seconds.", 10, 600),
            ),
            (
                "automationStartAtLogin",
                boolean("Start the automation host when the user signs in."),
            ),
            ("automationRunRetentionDays", retention()),
            ("automationAuditRetentionDays", retention()),
            ("automationTrashRetentionDays", retention()),
            (
                "clear",
                string_list(
                    "Settings to clear.",
                    &["workspaceDirectory", "defaultAgentProfileId"],
                ),
            ),
        ],
        &[],
    )
}

fn setting_value(arguments: &ToolArguments, property: &str) -> Option<String> {
    arguments
        .string(property)
        .or_else(|| {
            arguments
                .optional_flag(property)
                .map(|value| value.to_string())
        })
        .or_else(|| arguments.integer(property).map(|value| value.to_string()))
}

fn settings_invocation(arguments: &ToolArguments) -> Result<Invocation, ToolInputError> {
    let mut args = vec!["settings".to_owned(), "set".to_owned()];
    for (property, key) in SETTING_PROPERTIES {
        if let Some(value) = setting_value(arguments, property) {
            args.push(format!("{key}={value}"));
        }
    }
    for key in arguments.list("clear").unwrap_or_default() {
        args.push(format!("--unset={key}"));
    }
    if args.len() == 2 {
        return Err(ToolInputError(
            "Send at least one setting to change.".into(),
        ));
    }
    Ok(Invocation {
        group: "runtime",
        args,
        stdin: None,
    })
}

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![
        read(
            "get_version",
            "Get Version",
            "Show the Alera CLI and runtime host versions and the protocol and skill contract versions.",
            no_arguments,
            |_| Ok(Invocation::new("version", &[])),
        ),
        read(
            "get_runtime_settings",
            "Get Runtime Settings",
            "Show the runtime settings open to MCP clients: default agent profile, worktree folder, removal confirmations, AI Assist, and automation retention.",
            no_arguments,
            |_| Ok(Invocation::new("runtime", &["settings", "show"])),
        ),
        ToolSpec {
            idempotent: true,
            ..admin(
                "update_runtime_settings",
                "Update Runtime Settings",
                "Change runtime settings. Fields left out keep their values; list a setting in clear to remove it.",
                settings_schema,
                settings_invocation,
            )
        },
        read(
            "get_agent_integrations",
            "Get Agent Integrations",
            "Show which agents report their status to Alera through hooks.",
            no_arguments,
            |_| Ok(Invocation::new("runtime", &["agents", "status"])),
        ),
        ToolSpec {
            idempotent: true,
            omit_fields: SETTINGS_OUTSIDE_INTEGRATIONS,
            ..admin(
                "set_agent_integrations",
                "Set Agent Integrations",
                "Turn status hooks on or off for the listed agents.",
                || {
                    object(
                        &[
                            ("enabled", boolean("Turn the hooks on (true) or off (false).")),
                            ("agents", string_list("Agents to change.", INTEGRATION_AGENTS)),
                        ],
                        &["enabled", "agents"],
                    )
                },
                |arguments| {
                    let action = if arguments.flag("enabled") { "enable" } else { "disable" };
                    let mut invocation = Invocation::new("runtime", &["agents", action]);
                    invocation.args.extend(arguments.list("agents").unwrap_or_default());
                    Ok(invocation)
                },
            )
        },
        read(
            "get_resource_snapshot",
            "Get Resource Snapshot",
            "Show CPU and memory use of the host, the runtime, and each terminal session.",
            no_arguments,
            |_| Ok(Invocation::new("runtime", &["resources"])),
        ),
        ToolSpec {
            timeout_seconds: WAIT_TIMEOUT,
            ..read(
                "get_agent_quotas",
                "Get Agent Quotas",
                "Show usage limits for the enabled agent providers. Set refresh to fetch new numbers instead of the cached ones.",
                || object(&[("refresh", boolean("Fetch fresh numbers."))], &[]),
                |arguments| {
                    Ok(Invocation::new("agent-quota", &["show"])
                        .flag_if("--refresh", arguments.flag("refresh")))
                },
            )
        },
        ToolSpec {
            timeout_seconds: WAIT_TIMEOUT,
            idempotent: true,
            ..execute(
                "refresh_claude_quota",
                "Refresh Claude Quota",
                "Read one Claude account's usage again through the Claude terminal UI.",
                || object(&[("accountId", string("Claude account from get_agent_quotas. Defaults to default."))], &[]),
                |arguments| {
                    Ok(Invocation::new("agent-quota", &["refresh-claude"])
                        .option_if("--account-id", arguments.string("accountId")))
                },
            )
        },
        ToolSpec {
            timeout_seconds: WAIT_TIMEOUT,
            destructive: true,
            ..admin(
                "consume_codex_reset_credit",
                "Consume Codex Reset Credit",
                "Spend the Codex rate-limit reset credit offered in get_agent_quotas. A changed offer is refused.",
                || object(&[("offerRevision", string("Offer revision from the Codex quota snapshot."))], &["offerRevision"]),
                |arguments| {
                    Ok(Invocation::new("agent-quota", &["consume-codex-reset"])
                        .option("--offer-revision", arguments.required("offerRevision")?))
                },
            )
        },
        execute(
            "voice_speak",
            "Speak To The User",
            "Say a short message to the user through the Alera voice home agent.",
            || object(&[("text", text("What to say.", 2_000))], &["text"]),
            |arguments| Ok(Invocation::new("voice", &["speak"]).option("--text", arguments.required("text")?)),
        ),
        read(
            "voice_status",
            "Voice Status",
            "Show the voice home workspace, its agent session, and the speech pipeline.",
            no_arguments,
            |_| Ok(Invocation::new("voice", &["status"])),
        ),
    ]
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::SETTING_PROPERTIES;
    use crate::mcp_tools::find_tool;
    use crate::runtime_settings_commands::setting_keys;

    fn args(tool: &str, arguments: serde_json::Value) -> Vec<String> {
        find_tool(tool)
            .unwrap()
            .invocation(&arguments)
            .unwrap()
            .args
    }

    #[test]
    fn every_settings_property_writes_an_allowlisted_key() {
        let keys = setting_keys().collect::<Vec<_>>();
        assert_eq!(SETTING_PROPERTIES.len(), keys.len());
        for (_, key) in SETTING_PROPERTIES {
            assert!(keys.contains(key), "{key} is not allowlisted");
        }
    }

    #[test]
    fn settings_become_key_value_pairs() {
        assert_eq!(
            args(
                "update_runtime_settings",
                json!({
                    "aiAssistEnabled": false,
                    "automationRunRetentionDays": 10,
                    "aiAssistAgent": "claude",
                    "clear": ["workspaceDirectory"],
                }),
            ),
            [
                "settings",
                "set",
                "aiAssist.enabled=false",
                "aiAssist.agent=claude",
                "automation.runRetentionDays=10",
                "--unset=workspaceDirectory",
            ]
        );
        assert!(find_tool("update_runtime_settings")
            .unwrap()
            .invocation(&json!({}))
            .is_err());
        assert!(find_tool("update_runtime_settings")
            .unwrap()
            .invocation(&json!({ "aiAssistCustomCommand": "rm -rf /" }))
            .is_err());
    }

    #[test]
    fn the_default_profile_is_a_runtime_setting() {
        assert_eq!(
            args(
                "set_default_agent_profile",
                json!({ "profileId": "prof_1" })
            ),
            ["settings", "set", "defaultAgentProfileId=prof_1"]
        );
    }

    #[test]
    fn integrations_name_their_agents() {
        assert_eq!(
            args(
                "set_agent_integrations",
                json!({ "enabled": false, "agents": ["codex", "claude"] }),
            ),
            ["agents", "disable", "codex", "claude"]
        );
    }

    #[test]
    fn a_launch_sends_a_prompt_or_resumes_a_session() {
        let launch = find_tool("launch_agent").unwrap();
        let resumed = launch
            .invocation(&json!({
                "workspaceId": "ws",
                "profile": "prof_1",
                "resumeSessionId": "sess-1",
            }))
            .unwrap();
        assert!(resumed
            .args
            .contains(&"--resume-session-id=sess-1".to_owned()));
        assert_eq!(resumed.stdin, None);
        let prompted = launch
            .invocation(&json!({ "workspaceId": "ws", "profile": "prof_1", "prompt": "Fix it" }))
            .unwrap();
        assert!(prompted.args.contains(&"--prompt-stdin".to_owned()));
        assert_eq!(prompted.stdin.as_deref(), Some("Fix it"));
        assert!(launch
            .invocation(&json!({
                "workspaceId": "ws",
                "profile": "prof_1",
                "prompt": "Fix it",
                "resumeSessionId": "sess-1",
            }))
            .is_err());
    }

    #[test]
    fn profile_changes_send_managed_config_on_stdin() {
        let invocation = find_tool("update_agent_profile")
            .unwrap()
            .invocation(&json!({
                "profile": "prof_1",
                "expectedRevision": 3,
                "managedConfig": { "model": "opus" },
                "clearDescription": true,
                "showInNewTabMenu": false,
            }))
            .unwrap();
        assert_eq!(invocation.stdin.as_deref(), Some(r#"{"model":"opus"}"#));
        for expected in [
            "--profile-id=prof_1",
            "--expected-revision=3",
            "--managed-config-stdin",
            "--clear-description",
            "--show-in-new-tab-menu=false",
        ] {
            assert!(
                invocation.args.contains(&expected.to_owned()),
                "{expected} missing from {:?}",
                invocation.args
            );
        }
        assert!(find_tool("update_agent_profile")
            .unwrap()
            .invocation(&json!({
                "profile": "prof_1",
                "description": "x",
                "clearDescription": true,
            }))
            .is_err());
    }

    #[test]
    fn pulse_keeps_left_out_fields_unset() {
        assert_eq!(
            args(
                "configure_terminal_pulse",
                json!({ "handle": "t1", "enter": false })
            ),
            ["pulse", "set", "--handle=t1", "--enter=false"]
        );
        assert_eq!(
            args(
                "configure_terminal_pulse",
                json!({ "handle": "t1", "watch": "disarm" })
            ),
            ["pulse", "set", "--handle=t1", "--disarm"]
        );
    }
}
