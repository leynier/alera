//! Runtime automations and their runs.

use super::{execute, read};
use crate::mcp_tools::schema::{integer, object, string};
use crate::mcp_tools::{Invocation, ToolSpec};

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![
        read(
            "list_automations",
            "List Automations",
            "List runtime automations, optionally filtered by state, project, or search text.",
            || {
                object(
                    &[
                        ("state", string("Automation state.")),
                        ("projectId", string("Project id.")),
                        ("search", string("Text to search for.")),
                    ],
                    &[],
                )
            },
            |arguments| {
                Ok(Invocation::new("automation", &["list"])
                    .option_if("--state", arguments.string("state"))
                    .option_if("--project-id", arguments.string("projectId"))
                    .option_if("--search", arguments.string("search")))
            },
        ),
        read(
            "list_automation_runs",
            "List Automation Runs",
            "List automation runs, newest first, optionally for one automation.",
            || {
                object(
                    &[
                        ("automationId", string("Automation id.")),
                        ("limit", integer("Maximum runs (default 20).", 1, 100)),
                    ],
                    &[],
                )
            },
            |arguments| {
                Ok(Invocation::new("automation", &["runs"])
                    .option_if("--automation-id", arguments.string("automationId"))
                    .option(
                        "--limit",
                        arguments.integer("limit").unwrap_or(20).to_string(),
                    ))
            },
        ),
        execute(
            "run_automation",
            "Run Automation",
            "Start one run of an automation immediately.",
            || {
                object(
                    &[(
                        "automationId",
                        string("Automation id from list_automations."),
                    )],
                    &["automationId"],
                )
            },
            |arguments| {
                Ok(Invocation::new("automation", &["run-now"])
                    .option("--id", arguments.required("automationId")?))
            },
        ),
    ]
}
