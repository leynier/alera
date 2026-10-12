//! Recipe catalog tools over `alera orchestration recipe`.

use alera_core::runtime::WORKFLOW_DOCUMENT_MAX_BYTES;
use serde_json::{json, Value};

use super::{execute, read};
use crate::mcp_tools::schema::{integer, object, one_of, string, text};
use crate::mcp_tools::{Invocation, ToolArguments, ToolInputError, ToolSpec};

const RECIPE_LIMIT: u64 = WORKFLOW_DOCUMENT_MAX_BYTES as u64;

pub(super) fn tools() -> Vec<ToolSpec> {
    recipes()
}

fn recipes() -> Vec<ToolSpec> {
    vec![
        read(
            "list_recipes",
            "List Recipes",
            "List built-in and personal run recipes, plus a workspace's project recipes when workspaceId is given.",
            || object(&[("workspaceId", string("Workspace whose project recipes to include."))], &[]),
            |arguments| {
                Ok(Invocation::new("orchestration", &["recipe", "list"])
                    .option_if("--workspace", arguments.string("workspaceId")))
            },
        ),
        read(
            "show_recipe",
            "Show Recipe",
            "Show one run recipe with its digest, roles, and stages. Name it as list_recipes reports its source.",
            || object(&recipe_source_properties(""), &["origin", "id"]),
            |arguments| {
                Ok(Invocation::new("orchestration", &["recipe", "show"])
                    .option("--source", recipe_source(arguments, "", None)?.to_string()))
            },
        ),
        read(
            "validate_recipe",
            "Validate Recipe",
            "Check a portable run recipe (YAML) without saving or running it. Returns its digest and stage order.",
            || object(&[("document", text("Recipe YAML.", RECIPE_LIMIT))], &["document"]),
            |arguments| {
                Ok(Invocation::new("orchestration", &["recipe", "validate", "--stdin"])
                    .stdin(arguments.required("document")?))
            },
        ),
        execute(
            "save_personal_recipe",
            "Save Personal Recipe",
            "Create or update a personal run recipe from YAML. Updating one needs its current catalog revision.",
            || {
                object(
                    &[
                        ("document", text("Recipe YAML.", RECIPE_LIMIT)),
                        ("expectedRevision", integer("Catalog revision of the recipe being replaced.", 1, u64::MAX >> 11)),
                    ],
                    &["document"],
                )
            },
            |arguments| {
                Ok(Invocation::new("orchestration", &["recipe", "save-personal", "--stdin"])
                    .option_if("--expected-revision", arguments.integer("expectedRevision").map(|value| value.to_string()))
                    .stdin(arguments.required("document")?))
            },
        ),
        read(
            "preview_recipe_export",
            "Preview Recipe Export",
            "Preview writing a recipe into a workspace's project catalog (.alera/workflows). Returns the file before and after and the digest export_recipe needs.",
            export_schema,
            |arguments| export(arguments, false),
        ),
        execute(
            "export_recipe",
            "Export Recipe",
            "Write a recipe into a workspace's project catalog after preview_recipe_export. Fails if the file or document changed since the preview.",
            || {
                let mut schema = export_schema();
                schema["properties"]["expectedDigest"] = string("Digest from preview_recipe_export.");
                schema["required"] = json!(["workspaceId", "filename", "document", "expectedDigest"]);
                schema
            },
            |arguments| export(arguments, true),
        ),
    ]
}

fn export_schema() -> Value {
    object(
        &[
            (
                "workspaceId",
                string("Active local Git workspace whose project receives the recipe."),
            ),
            (
                "filename",
                string("File name such as release.yaml, inside .alera/workflows."),
            ),
            ("document", text("Recipe YAML.", RECIPE_LIMIT)),
        ],
        &["workspaceId", "filename", "document"],
    )
}

fn export(arguments: &ToolArguments, apply: bool) -> Result<Invocation, ToolInputError> {
    let invocation = Invocation::new("orchestration", &["recipe", "export", "--stdin"])
        .option("--workspace-id", arguments.required("workspaceId")?)
        .option("--filename", arguments.required("filename")?);
    let invocation = if apply {
        invocation
            .option("--expected-digest", arguments.required("expectedDigest")?)
            .flag("--apply")
    } else {
        invocation
    };
    Ok(invocation.stdin(arguments.required("document")?))
}

/// The recipe source properties, prefixed (`recipeOrigin`) or bare (`origin`).
fn recipe_source_properties(prefix: &str) -> Vec<(&'static str, Value)> {
    let names = source_names(prefix);
    vec![
        (
            names[0],
            one_of(
                "Where the recipe lives, as list_recipes reports it.",
                &["builtIn", "personal", "project"],
            ),
        ),
        (
            names[1],
            string("Recipe id, or for a project recipe its path, as list_recipes reports them."),
        ),
        (names[2], string("Workspace of a project recipe.")),
    ]
}

fn source_names(prefix: &str) -> [&'static str; 3] {
    if prefix.is_empty() {
        ["origin", "id", "workspaceId"]
    } else {
        ["recipeOrigin", "recipeId", "recipeWorkspaceId"]
    }
}

/// `{origin, id}`, or `{origin, workspaceId, path}` for a project recipe,
/// whose workspace defaults to `default_workspace`.
fn recipe_source(
    arguments: &ToolArguments,
    prefix: &str,
    default_workspace: Option<String>,
) -> Result<Value, ToolInputError> {
    let names = source_names(prefix);
    let origin = arguments.required(names[0])?;
    let id = arguments.required(names[1])?;
    if origin != "project" {
        return Ok(json!({ "origin": origin, "id": id }));
    }
    let workspace = arguments
        .string(names[2])
        .or(default_workspace)
        .ok_or_else(|| ToolInputError(format!("A project recipe needs `{}`.", names[2])))?;
    Ok(json!({ "origin": origin, "workspaceId": workspace, "path": id }))
}
