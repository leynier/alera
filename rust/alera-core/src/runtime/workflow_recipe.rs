use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use super::{parse_workflow_yaml, RoleContractV1};

pub async fn compile_workflow_recipe(document: String) -> Result<WorkflowRecipeV1> {
    super::workflow_catalog::workflow_blocking(move || WorkflowRecipeV1::from_yaml(&document)).await
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkflowRecipeV1 {
    pub version: u32,
    pub id: String,
    pub revision: u32,
    pub name: String,
    pub description: String,
    pub coordinator_instructions: String,
    pub roles: Vec<WorkflowRecipeRole>,
    pub contracts: Vec<RoleContractV1>,
    /// Every declared stage is mandatory in a proposed concrete plan.
    pub stages: Vec<WorkflowRecipeStage>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkflowRecipeRole {
    pub id: String,
    pub name: String,
    pub contract_id: String,
    pub contract_revision: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkflowRecipeStage {
    pub id: String,
    pub name: String,
    pub purpose: String,
    pub roles: Vec<String>,
    pub depends_on: Vec<String>,
    pub gate: Option<WorkflowHumanGate>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum WorkflowHumanGate {
    Foundation,
    Product,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "origin", rename_all = "camelCase", deny_unknown_fields)]
pub enum WorkflowRecipeSource {
    BuiltIn {
        id: String,
    },
    Personal {
        id: String,
    },
    Project {
        #[serde(rename = "workspaceId")]
        workspace_id: String,
        path: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkflowRecipeSnapshot {
    pub version: u32,
    pub source: WorkflowRecipeSource,
    pub recipe: WorkflowRecipeV1,
    pub digest: String,
}

impl WorkflowRecipeV1 {
    pub fn from_yaml(source: &str) -> Result<Self> {
        // Deserialization errors can echo arbitrary field values. Catalog
        // diagnostics identify the file but must not echo its contents.
        let recipe: Self = serde_json::from_value(parse_workflow_yaml(source)?)
            .map_err(|_| anyhow::anyhow!("workflow recipe does not match the versioned format"))?;
        recipe.validate()?;
        Ok(recipe)
    }

    pub fn content_digest(&self) -> Result<String> {
        let mut value = serde_json::to_value(self)?;
        value.sort_all_objects();
        Ok(format!("{:x}", Sha256::digest(serde_json::to_vec(&value)?)))
    }

    /// JSON is a YAML subset and provides deterministic, portable export
    /// without retaining unsupported YAML extensions or local profile data.
    pub fn portable_document(&self) -> Result<String> {
        self.validate()?;
        let document = format!("{}\n", serde_json::to_string_pretty(self)?);
        if document.len() > super::WORKFLOW_DOCUMENT_MAX_BYTES {
            return Ok(serde_json::to_string(self)?);
        }
        Ok(document)
    }
}

impl WorkflowRecipeSnapshot {
    pub fn freeze(source: WorkflowRecipeSource, recipe: WorkflowRecipeV1) -> Result<Self> {
        recipe.validate()?;
        source.validate(&recipe.id)?;
        let mut snapshot = Self {
            version: 1,
            source,
            recipe,
            digest: String::new(),
        };
        snapshot.digest = snapshot.content_digest()?;
        Ok(snapshot)
    }

    pub fn validate(&self) -> Result<()> {
        self.recipe.validate()?;
        self.source.validate(&self.recipe.id)?;
        if self.version != 1 || self.digest != self.content_digest()? {
            bail!("workflow recipe snapshot does not match its frozen contents");
        }
        Ok(())
    }

    fn content_digest(&self) -> Result<String> {
        let mut value = serde_json::json!([self.version, self.source, self.recipe]);
        value.sort_all_objects();
        Ok(format!("{:x}", Sha256::digest(serde_json::to_vec(&value)?)))
    }
}

impl WorkflowRecipeSource {
    pub(super) fn validate(&self, recipe_id: &str) -> Result<()> {
        use super::orchestration_role_contract::{artifact_path, portable_id};
        match self {
            Self::BuiltIn { id } | Self::Personal { id } => {
                portable_id(id)?;
                if id != recipe_id {
                    bail!("workflow source id does not match the recipe");
                }
            }
            Self::Project { workspace_id, path } => {
                if workspace_id.is_empty() || workspace_id.len() > 160 {
                    bail!("workflow source requires a workspace id");
                }
                artifact_path(path)?;
                let Some(file) = path.strip_prefix(".alera/workflows/") else {
                    bail!("project workflow source must be in .alera/workflows");
                };
                if file.contains('/') || !file.ends_with(".yaml") {
                    bail!("project workflow source must be a direct YAML file");
                }
            }
        }
        Ok(())
    }
}
