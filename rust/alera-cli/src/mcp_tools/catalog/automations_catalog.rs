//! Prompt templates, automation tags, and catalog export and import.

use serde_json::json;

use super::{json_object, with_object};
use crate::mcp_tools::catalog::{execute, no_arguments, read};
use crate::mcp_tools::schema::{object, string};
use crate::mcp_tools::{Invocation, ToolArguments, ToolInputError, ToolSpec};

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![
        read(
            "list_automation_templates",
            "List Automation Templates",
            "List the saved prompt templates automations can start from.",
            no_arguments,
            |_| Ok(Invocation::new("automation", &["templates"])),
        ),
        ToolSpec {
            idempotent: true,
            ..execute(
                "upsert_automation_template",
                "Save Automation Template",
                "Create or replace a prompt template by id, as Save as Template does.",
                || {
                    object(
                        &[(
                            "template",
                            json_object("Template with id, name, promptTemplate, and optional description and defaults. updatedAt is optional."),
                        )],
                        &["template"],
                    )
                },
                |arguments| {
                    with_object(
                        Invocation::new("automation", &["templates"]),
                        arguments,
                        "template",
                    )
                },
            )
        },
        read(
            "list_automation_tags",
            "List Automation Tags",
            "List the tags that group automations.",
            no_arguments,
            |_| Ok(Invocation::new("automation", &["tags"])),
        ),
        execute(
            "upsert_automation_tags",
            "Save Automation Tags",
            "Create a tag, or rename one by tagId, and set the tags of an automation. Pass tagName, automationId with tagIds, or both. To remove every tag, use update_automation with tagIds set to an empty list.",
            || {
                object(
                    &[
                        ("tagName", string("Name of the tag to create, or the new name of tagId.")),
                        ("tagId", string("Existing tag to rename.")),
                        ("automationId", string("Automation whose tags tagIds replaces.")),
                        ("tagIds", json!({
                            "type": "array",
                            "items": { "type": "string", "minLength": 1 },
                            "minItems": 1,
                            "uniqueItems": true,
                            "description": "Every tag id the automation should have.",
                        })),
                    ],
                    &[],
                )
            },
            upsert_tags,
        ),
        read(
            "export_automations",
            "Export Automations",
            "Export this runtime's automations, templates, and tags as a portable catalog that import_automations accepts.",
            no_arguments,
            |_| Ok(Invocation::new("automation", &["export"])),
        ),
        execute(
            "import_automations",
            "Import Automations",
            "Import a catalog from export_automations. Imported automations keep their ids unless remapped.",
            || {
                object(
                    &[
                        ("bundle", json_object("Catalog object as export_automations returns it.")),
                        ("remap", json_object("Map of source id to target id, for projects, profiles, or workspaces that differ on this runtime.")),
                    ],
                    &["bundle"],
                )
            },
            import_automations,
        ),
    ]
}

fn upsert_tags(arguments: &ToolArguments) -> Result<Invocation, ToolInputError> {
    let name = arguments.string("tagName");
    let automation = arguments.string("automationId");
    let tag_ids = arguments.list("tagIds").unwrap_or_default();
    if arguments.string("tagId").is_some() && name.is_none() {
        return Err(ToolInputError("tagId needs tagName, the new name.".into()));
    }
    if automation.is_some() == tag_ids.is_empty() {
        return Err(ToolInputError(
            "Pass automationId together with tagIds.".into(),
        ));
    }
    if name.is_none() && automation.is_none() {
        return Err(ToolInputError(
            "Pass tagName, or automationId with tagIds.".into(),
        ));
    }
    let mut invocation = Invocation::new("automation", &["tags"])
        .option_if("--name", name)
        .option_if("--id", arguments.string("tagId"))
        .option_if("--automation-id", automation);
    for tag_id in tag_ids {
        invocation = invocation.option("--assign", tag_id);
    }
    Ok(invocation)
}

fn import_automations(arguments: &ToolArguments) -> Result<Invocation, ToolInputError> {
    let mut invocation = Invocation::new("automation", &["import"]);
    for (source, target) in arguments.object("remap").into_iter().flatten() {
        let Some(target) = target.as_str().filter(|target| !target.is_empty()) else {
            return Err(ToolInputError(format!(
                "remap of `{source}` must be a non-empty id."
            )));
        };
        if source.is_empty() || source.contains('=') {
            return Err(ToolInputError("remap keys must be ids.".into()));
        }
        invocation = invocation.option("--remap", format!("{source}={target}"));
    }
    with_object(invocation, arguments, "bundle")
}
