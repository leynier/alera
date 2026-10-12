use std::io::Read;

use alera_core::runtime::{WorkflowRecipeSource, WORKFLOW_DOCUMENT_MAX_BYTES};
use anyhow::{bail, Result};
use serde_json::{json, Value};

use crate::cli::RuntimeDirArgs;
use crate::cli_run_recipes::{RecipeAction, RecipeDocumentArgs};
use crate::orchestration_commands::request_value_with_capability;
use crate::terminal_host::protocol::RUNTIME_HOST_RECIPES_CAPABILITY;

pub(crate) async fn run_recipes(
    runtime: &RuntimeDirArgs,
    action: RecipeAction,
    json_output: bool,
) -> i32 {
    let (verb, payload) = match request_payload(action) {
        Ok(request) => request,
        Err(error) => {
            eprintln!("{error}");
            return 64;
        }
    };
    match request_value_with_capability(
        runtime,
        RUNTIME_HOST_RECIPES_CAPABILITY,
        verb,
        payload,
        Some(30_000),
    )
    .await
    {
        Ok(value) => {
            if json_output {
                println!(
                    "{}",
                    serde_json::to_string_pretty(&value).unwrap_or_default()
                );
            } else if verb == "recipes.catalog" {
                for entry in value["entries"].as_array().into_iter().flatten() {
                    println!(
                        "{}\t{}\t{}",
                        entry["source"],
                        entry["name"].as_str().unwrap_or("Invalid Recipe"),
                        entry["error"].as_str().unwrap_or("valid")
                    );
                }
                if let Some(error) = value["projectError"].as_str() {
                    eprintln!("Project catalog: {error}");
                }
            } else {
                println!(
                    "{}",
                    serde_json::to_string_pretty(&value).unwrap_or_default()
                );
            }
            0
        }
        Err(error) => {
            eprintln!("{error}");
            1
        }
    }
}

fn request_payload(action: RecipeAction) -> Result<(&'static str, Value)> {
    Ok(match action {
        RecipeAction::List { workspace } => ("recipes.catalog", json!({"workspaceId": workspace})),
        RecipeAction::Show { source } => {
            if source.len() > 2048 {
                bail!("recipe source exceeds the size limit");
            }
            let source: WorkflowRecipeSource = serde_json::from_str(&source)?;
            ("recipes.recipe", json!({"source": source}))
        }
        RecipeAction::Validate(input) => {
            ("recipes.validate", json!({"document": document(input)?}))
        }
        RecipeAction::SavePersonal {
            input,
            expected_revision,
        } => {
            if expected_revision.is_some_and(|revision| revision < 1) {
                bail!("expected revision must be positive");
            }
            (
                "recipes.savePersonal",
                json!({"document": document(input)?, "expectedRevision": expected_revision}),
            )
        }
        RecipeAction::Export {
            input,
            workspace_id,
            filename,
            expected_digest,
            apply,
        } => (
            if apply {
                "recipes.applyExport"
            } else {
                "recipes.previewExport"
            },
            json!({
                "workspaceId": workspace_id,
                "filename": filename,
                "document": document(input)?,
                "expectedDigest": expected_digest,
            }),
        ),
    })
}

fn document(input: RecipeDocumentArgs) -> Result<String> {
    let source = if input.stdin {
        let mut bytes = Vec::new();
        std::io::stdin()
            .lock()
            .take((WORKFLOW_DOCUMENT_MAX_BYTES + 1) as u64)
            .read_to_end(&mut bytes)?;
        String::from_utf8(bytes)?
    } else {
        input.document.unwrap_or_default()
    };
    if source.is_empty() || source.len() > WORKFLOW_DOCUMENT_MAX_BYTES {
        bail!("recipe document is empty or exceeds the size limit");
    }
    Ok(source)
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::Parser;

    #[test]
    fn recipe_cli_requires_explicit_input_and_source() {
        for arguments in [
            vec!["validate"],
            vec!["validate", "--stdin", "--document", "{}"],
            vec!["show"],
            vec!["save-personal"],
        ] {
            assert!(crate::cli::Cli::try_parse_from(
                ["alera", "orchestration", "recipe"]
                    .into_iter()
                    .chain(arguments)
            )
            .is_err());
        }
        for arguments in [
            vec!["validate", "--stdin"],
            vec!["list", "--workspace", "source"],
            vec![
                "save-personal",
                "--document",
                "{}",
                "--expected-revision",
                "2",
            ],
        ] {
            crate::cli::Cli::try_parse_from(
                ["alera", "orchestration", "recipe"]
                    .into_iter()
                    .chain(arguments),
            )
            .unwrap();
        }
    }

    #[test]
    fn recipe_cli_uses_catalog_verbs_and_rejects_ambiguous_origins() {
        let (verb, payload) = request_payload(RecipeAction::Show {
            source: r#"{"origin":"personal","id":"quick-fix"}"#.into(),
        })
        .unwrap();
        assert_eq!(verb, "recipes.recipe");
        assert_eq!(payload["source"]["origin"], "personal");
        assert!(request_payload(RecipeAction::Show {
            source: r#"{"id":"quick-fix"}"#.into()
        })
        .is_err());
        let (verb, payload) = request_payload(RecipeAction::Export {
            input: RecipeDocumentArgs {
                document: Some("name: x".into()),
                stdin: false,
            },
            workspace_id: "ws".into(),
            filename: "x.yaml".into(),
            expected_digest: None,
            apply: false,
        })
        .unwrap();
        assert_eq!(verb, "recipes.previewExport");
        assert_eq!(payload["filename"], "x.yaml");
        assert!(crate::cli::Cli::try_parse_from([
            "alera",
            "orchestration",
            "recipe",
            "export",
            "--stdin",
            "--workspace-id",
            "ws",
            "--filename",
            "x.yaml",
            "--apply",
        ])
        .is_err());
        assert!(document(RecipeDocumentArgs {
            document: Some("x".repeat(WORKFLOW_DOCUMENT_MAX_BYTES + 1)),
            stdin: false
        })
        .is_err());
    }
}
