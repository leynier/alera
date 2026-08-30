use std::sync::{Arc, OnceLock};

use anyhow::{anyhow, bail, Result};
use serde::{Deserialize, Serialize};
use tokio::sync::Semaphore;

use super::workflow_project_files::read_project_workflow_documents;
use super::{
    builtin_workflow_recipes, ProjectKind, RuntimeStore, WorkflowRecipeSource, WorkflowRecipeV1,
    WorkspaceStatus, LOCAL_HOST_ID,
};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowCatalogEntry {
    pub source: WorkflowRecipeSource,
    pub name: Option<String>,
    pub description: Option<String>,
    pub recipe_revision: Option<u32>,
    pub catalog_revision: Option<i64>,
    pub digest: Option<String>,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowCatalog {
    pub entries: Vec<WorkflowCatalogEntry>,
    pub project_error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowCatalogRecipe {
    pub source: WorkflowRecipeSource,
    pub catalog_revision: Option<i64>,
    pub digest: String,
    pub recipe: WorkflowRecipeV1,
}

pub(super) struct CatalogContents {
    pub catalog: WorkflowCatalog,
    pub recipes: Vec<WorkflowCatalogRecipe>,
}

impl RuntimeStore {
    pub async fn workflow_catalog(&self, workspace_id: Option<&str>) -> Result<WorkflowCatalog> {
        Ok(self.workflow_catalog_contents(workspace_id).await?.catalog)
    }

    pub async fn workflow_catalog_recipe(
        &self,
        source: &WorkflowRecipeSource,
    ) -> Result<WorkflowCatalogRecipe> {
        let workspace_id = match source {
            WorkflowRecipeSource::Project { workspace_id, .. } => Some(workspace_id.as_str()),
            _ => None,
        };
        let contents = self.workflow_catalog_contents(workspace_id).await?;
        if let Some(error) = contents.catalog.project_error {
            bail!("project workflow catalog is unavailable: {error}");
        }
        contents
            .recipes
            .into_iter()
            .find(|recipe| &recipe.source == source)
            .ok_or_else(|| anyhow!("workflow recipe is missing or invalid; refresh its catalog"))
    }

    async fn workflow_catalog_contents(
        &self,
        workspace_id: Option<&str>,
    ) -> Result<CatalogContents> {
        let workspace = if let Some(id) = workspace_id {
            let workspace = self
                .find_workspace(id)
                .await?
                .ok_or_else(|| anyhow!("workflow workspace not found"))?;
            if workspace.status != WorkspaceStatus::Active || workspace.host_id != LOCAL_HOST_ID {
                bail!("workflow catalogs require an active workspace on this host");
            }
            let project = self
                .find_project(&workspace.project_id)
                .await?
                .ok_or_else(|| anyhow!("workflow project not found"))?;
            if project.kind != ProjectKind::GitRepository {
                bail!("workflow catalogs require a Git project");
            }
            Some(workspace)
        } else {
            None
        };
        let personal = self.personal_workflow_documents().await?;
        workflow_blocking(move || {
            let mut contents = CatalogContents {
                catalog: WorkflowCatalog {
                    entries: Vec::new(),
                    project_error: None,
                },
                recipes: Vec::new(),
            };
            for recipe in builtin_workflow_recipes() {
                contents.add(
                    WorkflowRecipeSource::BuiltIn {
                        id: recipe.id.clone(),
                    },
                    None,
                    Ok(recipe.clone()),
                );
            }
            for (id, revision, document) in personal {
                contents.add(
                    WorkflowRecipeSource::Personal { id },
                    Some(revision),
                    WorkflowRecipeV1::from_yaml(&document),
                );
            }
            if let Some(workspace) = workspace {
                match read_project_workflow_documents(std::path::Path::new(&workspace.path)) {
                    Ok(documents) => {
                        for document in documents {
                            let recipe = document
                                .source
                                .and_then(|source| WorkflowRecipeV1::from_yaml(&source));
                            contents.add(
                                WorkflowRecipeSource::Project {
                                    workspace_id: workspace.id.clone(),
                                    path: document.path,
                                },
                                None,
                                recipe,
                            );
                        }
                    }
                    Err(error) => contents.catalog.project_error = Some(error.to_string()),
                }
            }
            Ok(contents)
        })
        .await
    }
}

impl CatalogContents {
    fn add(
        &mut self,
        source: WorkflowRecipeSource,
        catalog_revision: Option<i64>,
        recipe: Result<WorkflowRecipeV1>,
    ) {
        let result = recipe.and_then(|recipe| {
            source.validate(&recipe.id)?;
            Ok(WorkflowCatalogRecipe {
                digest: recipe.content_digest()?,
                recipe,
                source: source.clone(),
                catalog_revision,
            })
        });
        let entry = match result {
            Ok(record) => {
                let entry = WorkflowCatalogEntry {
                    source,
                    catalog_revision,
                    name: Some(record.recipe.name.clone()),
                    description: Some(record.recipe.description.clone()),
                    recipe_revision: Some(record.recipe.revision),
                    digest: Some(record.digest.clone()),
                    error: None,
                };
                self.recipes.push(record);
                entry
            }
            Err(error) => WorkflowCatalogEntry {
                source,
                catalog_revision,
                name: None,
                description: None,
                recipe_revision: None,
                digest: None,
                error: Some(error.to_string()),
            },
        };
        self.catalog.entries.push(entry);
    }
}

pub(super) async fn workflow_blocking<T: Send + 'static>(
    work: impl FnOnce() -> Result<T> + Send + 'static,
) -> Result<T> {
    static SLOTS: OnceLock<Arc<Semaphore>> = OnceLock::new();
    let permit = SLOTS
        .get_or_init(|| Arc::new(Semaphore::new(2)))
        .clone()
        .acquire_owned()
        .await?;
    // A timed-out caller cannot free this slot while filesystem/parsing work
    // still runs. Repeated disconnects therefore cannot flood blocking workers.
    tokio::task::spawn_blocking(move || {
        let _permit = permit;
        work()
    })
    .await?
}
