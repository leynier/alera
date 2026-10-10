//! Automation authoring, state changes, run control, and the shared catalog
//! of templates and tags. Definitions travel to the CLI on stdin.

use serde_json::{json, Value};

use super::{execute, read};
use crate::mcp_tools::schema::{boolean, integer, object, one_of, string};
use crate::mcp_tools::{Invocation, ToolArguments, ToolInputError, ToolSpec};

const REQUEST_KEY: Option<&str> = Some("--request-key");
const DEFAULT_EXTENSION_SECONDS: u64 = 3600;
const MAX_EXTENSION_SECONDS: u64 = 30 * 24 * 3600;

pub(super) fn json_object(description: &str) -> Value {
    json!({ "type": "object", "description": description })
}

fn automation_id() -> Value {
    string("Automation id from list_automations.")
}

fn run_id() -> Value {
    string("Automation run id from list_automation_runs.")
}

/// Sends a JSON object argument to the CLI on stdin.
pub(super) fn with_object(
    invocation: Invocation,
    arguments: &ToolArguments,
    name: &str,
) -> Result<Invocation, ToolInputError> {
    let value = arguments
        .object(name)
        .ok_or_else(|| ToolInputError(format!("Missing required argument `{name}`.")))?;
    Ok(invocation
        .option("--file", "-")
        .stdin(Value::Object(value.clone()).to_string()))
}

#[path = "automations_catalog.rs"]
mod automations_catalog;

pub(super) fn tools() -> Vec<ToolSpec> {
    let mut tools = vec![
        read(
            "show_automation",
            "Show Automation",
            "Show one automation with its definition, readiness, next occurrences, recent runs, and audit history.",
            || object(&[("automationId", automation_id())], &["automationId"]),
            |arguments| {
                Ok(Invocation::new("automation", &["show"])
                    .option("--id", arguments.required("automationId")?))
            },
        ),
        read(
            "show_automation_run",
            "Show Automation Run",
            "Show one automation run with its attempts and the automation definition it ran.",
            || object(&[("runId", run_id())], &["runId"]),
            |arguments| {
                Ok(Invocation::new("automation", &["run-show"])
                    .option("--id", arguments.required("runId")?))
            },
        ),
        ToolSpec {
            client_request_flag: REQUEST_KEY,
            ..execute(
                "create_automation",
                "Create Automation",
                "Create an automation from a JSON definition, as the automation editor saves it. It starts active unless draft is true or the definition sets state to draft. Check the definition first with check_automation_readiness.",
                || {
                    object(
                        &[
                            ("definition", json_object("Automation definition: name, promptTemplate, schedule ({recurring: {cron, timezone}} or {oneTime: {at, timezone}}), target, and optional policies, tagIds, and projectId.")),
                            ("draft", boolean("Save as a draft instead of activating it.")),
                        ],
                        &["definition"],
                    )
                },
                |arguments| {
                    let invocation = Invocation::new("automation", &["create"])
                        .flag_if("--draft", arguments.flag("draft"));
                    with_object(invocation, arguments, "definition")
                },
            )
        },
        execute(
            "update_automation",
            "Update Automation",
            "Change fields of an automation, as saving the automation editor does. Fields not given keep their value.",
            || {
                object(
                    &[
                        ("automationId", automation_id()),
                        ("changes", json_object("Definition fields to replace, such as name, promptTemplate, schedule, target, or tagIds.")),
                        ("expectedRevision", integer("Refuse the change if the automation changed since this revision.", 0, u64::MAX >> 11)),
                    ],
                    &["automationId", "changes"],
                )
            },
            |arguments| {
                let invocation = Invocation::new("automation", &["edit"])
                    .option("--id", arguments.required("automationId")?)
                    .option_if(
                        "--expected-revision",
                        arguments.integer("expectedRevision").map(|value| value.to_string()),
                    );
                with_object(invocation, arguments, "changes")
            },
        ),
        ToolSpec {
            client_request_flag: REQUEST_KEY,
            ..execute(
                "clone_automation",
                "Clone Automation",
                "Create a new automation with the settings and target of an existing one, as the Clone action does. The copy is named after the original followed by Copy unless a name is given.",
                || {
                    object(
                        &[
                            ("automationId", automation_id()),
                            ("name", string("Name of the copy.")),
                            ("draft", boolean("Save the copy as a draft instead of activating it.")),
                        ],
                        &["automationId"],
                    )
                },
                |arguments| {
                    Ok(Invocation::new("automation", &["clone"])
                        .option("--id", arguments.required("automationId")?)
                        .option_if("--name", arguments.string("name"))
                        .flag_if("--draft", arguments.flag("draft")))
                },
            )
        },
        read(
            "check_automation_readiness",
            "Check Automation Readiness",
            "Validate a full or partial automation definition without saving it, and list the fields to fix.",
            || object(&[("definition", json_object("Automation definition, as create_automation takes it."))], &["definition"]),
            |arguments| with_object(Invocation::new("automation", &["readiness"]), arguments, "definition"),
        ),
        read(
            "preview_automation_schedule",
            "Preview Automation Schedule",
            "Preview the next occurrences of a recurring cron schedule or a one-time date.",
            || {
                object(
                    &[
                        ("kind", one_of("recurring takes a cron expression; oneTime takes a date and time.", &["recurring", "oneTime"])),
                        ("value", string("Cron expression such as 0 9 * * 1-5, or an ISO 8601 date and time.")),
                        ("timezone", string("IANA time zone such as Europe/Madrid (default UTC).")),
                    ],
                    &["kind", "value"],
                )
            },
            |arguments| {
                let flag = match arguments.required("kind")?.as_str() {
                    "oneTime" => "--at",
                    _ => "--cron",
                };
                Ok(Invocation::new("automation", &["preview-schedule"])
                    .option(flag, arguments.required("value")?)
                    .option_if("--timezone", arguments.string("timezone")))
            },
        ),
    ];
    tools.extend(state_changes());
    tools.extend(run_control());
    tools.extend(automations_catalog::tools());
    tools
}

fn state_change(
    name: &'static str,
    title: &'static str,
    description: &'static str,
    build: super::Build,
) -> ToolSpec {
    execute(
        name,
        title,
        description,
        || {
            object(
                &[
                    ("automationId", automation_id()),
                    ("reason", string("Why, recorded in the audit history.")),
                    ("activeRuns", one_of("With active runs, keep them running or cancel them. Required when pausing an automation that has active runs.", &["continue-active", "cancel-active"])),
                ],
                &["automationId"],
            )
        },
        build,
    )
}

fn state_invocation(
    action: &'static str,
    arguments: &ToolArguments,
) -> Result<Invocation, ToolInputError> {
    Ok(Invocation::new("automation", &[action])
        .option("--id", arguments.required("automationId")?)
        .option_if("--reason", arguments.string("reason"))
        .option_if("--active-runs", arguments.string("activeRuns")))
}

fn state_changes() -> Vec<ToolSpec> {
    vec![
        state_change("pause_automation", "Pause Automation", "Pause an automation so it stops scheduling runs. With active runs, choose activeRuns: continue-active keeps them, cancel-active cancels them.", |arguments| state_invocation("pause", arguments)),
        state_change("resume_automation", "Resume Automation", "Activate a paused or draft automation. Fails with the fields to fix when it is not ready.", |arguments| state_invocation("resume", arguments)),
        ToolSpec {
            destructive: true,
            ..state_change("trash_automation", "Trash Automation", "Move an automation to the trash. It can be restored with restore_automation until it is purged.", |arguments| state_invocation("trash", arguments))
        },
        state_change("restore_automation", "Restore Automation", "Restore a trashed automation, paused, or completed if it was completed before.", |arguments| state_invocation("restore", arguments)),
        ToolSpec {
            destructive: true,
            ..execute(
                "purge_automations",
                "Purge Automations",
                "Permanently delete every automation that has been in the trash for at least 30 days, as Purge in the trash view does.",
                super::no_arguments,
                |_| Ok(Invocation::new("automation", &["purge"])),
            )
        },
    ]
}

fn run_control() -> Vec<ToolSpec> {
    vec![
        ToolSpec {
            destructive: true,
            idempotent: true,
            ..execute(
                "cancel_automation_run",
                "Cancel Automation Run",
                "Cancel a queued, running, or waiting automation run, as Cancel in the run view does.",
                || object(&[("runId", run_id())], &["runId"]),
                |arguments| {
                    Ok(Invocation::new("automation", &["cancel"])
                        .option("--run", arguments.required("runId")?)
                        .flag("--use-run-identity"))
                },
            )
        },
        execute(
            "resume_automation_run",
            "Resume Automation Run",
            "Resume a run that is waiting for you, so its agent continues.",
            || object(&[("runId", run_id())], &["runId"]),
            |arguments| {
                Ok(Invocation::new("automation", &["wait"])
                    .option("--run", arguments.required("runId")?)
                    .flag("--resume")
                    .flag("--use-run-identity"))
            },
        ),
        execute(
            "extend_automation_run",
            "Extend Automation Run",
            "Extend the deadline of a run that is waiting for you, by seconds (default one hour) or until a date and time.",
            || {
                object(
                    &[
                        ("runId", run_id()),
                        ("seconds", integer("Seconds to add (default 3600).", 1, MAX_EXTENSION_SECONDS)),
                        ("until", string("New deadline as an ISO 8601 date and time, instead of seconds.")),
                    ],
                    &["runId"],
                )
            },
            extend_run,
        ),
        execute(
            "take_over_automation_run",
            "Take Over Automation Run",
            "Take over the terminal of an automation run, as Take Over in the app does. The automation stops driving the agent and the terminal stays open for a person.",
            || object(&[("runId", run_id())], &["runId"]),
            |arguments| {
                Ok(Invocation::new("automation", &["take-over"])
                    .option("--run", arguments.required("runId")?))
            },
        ),
    ]
}

fn extend_run(arguments: &ToolArguments) -> Result<Invocation, ToolInputError> {
    let invocation = Invocation::new("automation", &["extend"])
        .option("--run", arguments.required("runId")?)
        .flag("--use-run-identity");
    match (arguments.integer("seconds"), arguments.string("until")) {
        (Some(_), Some(_)) => Err(ToolInputError("Pass seconds or until, not both.".into())),
        (None, Some(until)) => Ok(invocation.option("--until", until)),
        (seconds, None) => Ok(invocation.option(
            "--seconds",
            seconds.unwrap_or(DEFAULT_EXTENSION_SECONDS).to_string(),
        )),
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use crate::mcp_tools::find_tool;

    fn args(tool: &str, arguments: serde_json::Value) -> Result<Vec<String>, String> {
        find_tool(tool)
            .unwrap()
            .invocation(&arguments)
            .map(|invocation| invocation.args)
            .map_err(|error| error.0)
    }

    #[test]
    fn definitions_travel_on_stdin() {
        let invocation = find_tool("create_automation")
            .unwrap()
            .invocation(
                &json!({"definition": {"name": "Nightly"}, "clientRequestId": "request-0001"}),
            )
            .unwrap();
        assert_eq!(invocation.stdin.as_deref(), Some(r#"{"name":"Nightly"}"#));
        assert!(invocation.args.contains(&"--file=-".to_owned()));
        assert!(invocation
            .args
            .contains(&"--request-key=request-0001".to_owned()));
        assert!(args("create_automation", json!({"definition": "text"})).is_err());
    }

    #[test]
    fn run_control_uses_the_recorded_run_identity() {
        let extend = args("extend_automation_run", json!({"runId": "r"})).unwrap();
        assert!(extend.contains(&"--seconds=3600".to_owned()));
        assert!(extend.contains(&"--use-run-identity".to_owned()));
        assert!(args(
            "extend_automation_run",
            json!({"runId": "r", "seconds": 5, "until": "x"})
        )
        .is_err());
        let cancel = args("cancel_automation_run", json!({"runId": "r"})).unwrap();
        assert!(cancel.contains(&"--use-run-identity".to_owned()));
    }

    #[test]
    fn tags_and_imports_validate_their_shape() {
        assert!(args("upsert_automation_tags", json!({})).is_err());
        assert!(args("upsert_automation_tags", json!({"automationId": "a"})).is_err());
        let assign = args(
            "upsert_automation_tags",
            json!({"automationId": "a", "tagIds": ["t1", "t2"]}),
        )
        .unwrap();
        assert_eq!(
            assign
                .iter()
                .filter(|arg| arg.starts_with("--assign="))
                .count(),
            2
        );
        let import = args(
            "import_automations",
            json!({"bundle": {}, "remap": {"p1": "p2"}}),
        )
        .unwrap();
        assert!(import.contains(&"--remap=p1=p2".to_owned()));
        assert!(args(
            "import_automations",
            json!({"bundle": {}, "remap": {"p1": 3}})
        )
        .is_err());
        let run = args(
            "run_automation",
            json!({"automationId": "a", "precheck": "skip"}),
        )
        .unwrap();
        assert!(run.contains(&"--skip-precheck".to_owned()));
    }
}
