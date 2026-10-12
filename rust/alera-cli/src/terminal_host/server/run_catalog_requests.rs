use std::sync::{Arc, OnceLock};
use std::time::Duration;

use alera_core::runtime::{
    compile_workflow_recipe, RuntimeStore, WorkflowExportRequest, WorkflowRecipeSource,
    WORKFLOW_DOCUMENT_MAX_BYTES,
};
use serde::Deserialize;
use serde_json::{json, Value};
use tokio::sync::Semaphore;

use crate::terminal_host::client::ClientFrame;
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::{error_response, ok_response};

use super::{ServerActor, ServerCommand};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CatalogQuery {
    workspace_id: Option<String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct RecipeQuery {
    source: WorkflowRecipeSource,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SaveRecipe {
    document: String,
    expected_revision: Option<i64>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ValidateRecipe {
    document: String,
}

enum CatalogRequest {
    List(CatalogQuery),
    Get(RecipeQuery),
    Validate(ValidateRecipe),
    Save(SaveRecipe),
    Export(WorkflowExportRequest, bool),
}

struct CatalogResponse {
    value: Value,
    changed: Option<(WorkflowRecipeSource, i64)>,
}

impl ServerActor {
    /// `recipes.*`. Authorization (mobile may only read) is checked by the
    /// caller against the mobile allowlist.
    pub(super) fn start_recipe_request(
        &self,
        client_id: u64,
        request_id: i64,
        request_type: &str,
        payload: &Value,
    ) -> HostResult<()> {
        let client = self
            .clients
            .get(&client_id)
            .ok_or_else(|| HostError::state("client closed"))?;
        if payload
            .get("document")
            .and_then(Value::as_str)
            .is_some_and(|source| source.len() > WORKFLOW_DOCUMENT_MAX_BYTES)
        {
            return Err(HostError::format(
                "workflow document exceeds the byte limit",
            ));
        }
        let request = match request_type {
            "recipes.catalog" => CatalogRequest::List(parse(payload)?),
            "recipes.recipe" => CatalogRequest::Get(parse(payload)?),
            "recipes.validate" => CatalogRequest::Validate(parse(payload)?),
            "recipes.savePersonal" => CatalogRequest::Save(parse(payload)?),
            "recipes.previewExport" => CatalogRequest::Export(parse(payload)?, false),
            "recipes.applyExport" => CatalogRequest::Export(parse(payload)?, true),
            _ => return Err(HostError::format("unknown recipes request")),
        };
        static QUEUE: OnceLock<Arc<Semaphore>> = OnceLock::new();
        let permit = QUEUE
            .get_or_init(|| Arc::new(Semaphore::new(8)))
            .clone()
            .try_acquire_owned()
            .map_err(|_| HostError::state("workflow catalog is busy; retry shortly"))?;
        let inbox = self.inbox.clone();
        let store = self.runtime_store.clone();
        let client = client.handle.clone();
        tokio::spawn(async move {
            let _permit = permit;
            let result = tokio::time::timeout(Duration::from_secs(25), request.execute(store))
                .await
                .unwrap_or_else(|_| {
                    Err(HostError::state(
                        "workflow catalog request timed out; refresh before retrying a save",
                    ))
                });
            let response = match result {
                Ok(response) => {
                    if let Some((source, catalog_revision)) = response.changed {
                        // Resolve recipients in the actor after persistence, even if
                        // the initiating client disconnected while the save ran.
                        let _ = inbox.send(ServerCommand::WorkflowCatalogChanged {
                            source,
                            catalog_revision,
                        });
                    }
                    ok_response(request_id, response.value)
                }
                Err(error) => error_response(request_id, &error),
            };
            let _ = client.send_control(ClientFrame::Json(response));
        });
        Ok(())
    }
}

impl CatalogRequest {
    async fn execute(self, store: RuntimeStore) -> HostResult<CatalogResponse> {
        let value = match self {
            Self::Export(query, apply) => serde_json::to_value(
                store
                    .export_workflow_recipe(query, apply)
                    .await
                    .map_err(state)?,
            ),
            Self::List(query) => serde_json::to_value(
                store
                    .workflow_catalog(query.workspace_id.as_deref())
                    .await
                    .map_err(state)?,
            ),
            Self::Get(query) => serde_json::to_value(
                store
                    .workflow_catalog_recipe(&query.source)
                    .await
                    .map_err(state)?,
            ),
            Self::Save(query) => {
                let saved = store
                    .save_personal_workflow_recipe(query.document, query.expected_revision)
                    .await
                    .map_err(state)?;
                return Ok(CatalogResponse {
                    value: serde_json::to_value(&saved).map_err(state)?,
                    changed: Some((
                        saved.source,
                        saved.catalog_revision.ok_or_else(|| {
                            HostError::state("saved personal recipe has no catalog revision")
                        })?,
                    )),
                });
            }
            Self::Validate(query) => {
                let recipe = compile_workflow_recipe(query.document)
                    .await
                    .map_err(state)?;
                Ok(
                    json!({"digest": recipe.content_digest().map_err(state)?, "stageOrder": recipe.stage_order().map_err(state)?, "recipe": recipe}),
                )
            }
        };
        Ok(CatalogResponse {
            value: value.map_err(state)?,
            changed: None,
        })
    }
}

fn parse<T: serde::de::DeserializeOwned>(payload: &Value) -> HostResult<T> {
    serde_json::from_value(payload.clone())
        .map_err(|_| HostError::format("invalid workflow catalog request"))
}

fn state(error: impl std::fmt::Display) -> HostError {
    HostError::state(error.to_string())
}
