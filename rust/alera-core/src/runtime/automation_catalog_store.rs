use anyhow::{anyhow, bail, Result};
use chrono::Utc;
use serde_json::Value;
use sqlx::Row;
use std::collections::BTreeMap;
use uuid::Uuid;

use super::{
    format_timestamp, AutomationActor, AutomationAgentPolicy, AutomationDefinition,
    AutomationExportBundle, AutomationImportBundle, AutomationProjectPolicy, AutomationState,
    AutomationTag, AutomationTemplate, RuntimeStore,
};

impl RuntimeStore {
    pub async fn list_automation_templates(&self) -> Result<Vec<AutomationTemplate>> {
        let rows = sqlx::query(
            "SELECT dataJson FROM automationTemplates ORDER BY name COLLATE NOCASE ASC",
        )
        .fetch_all(self.pool())
        .await?;
        rows.into_iter()
            .map(|row| {
                let data: String = row.try_get("dataJson")?;
                Ok(serde_json::from_str(&data)?)
            })
            .collect()
    }

    pub async fn upsert_automation_template(
        &self,
        mut template: AutomationTemplate,
    ) -> Result<AutomationTemplate> {
        template.name = template.name.trim().to_string();
        template.prompt_template = template.prompt_template.trim().to_string();
        if template.name.is_empty() || template.prompt_template.is_empty() {
            bail!("template name and prompt are required");
        }
        if template.id.trim().is_empty() {
            template.id = Uuid::new_v4().to_string();
        }
        template.updated_at = Utc::now();
        sqlx::query(
            "INSERT INTO automationTemplates (id, name, dataJson, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?) \
             ON CONFLICT(id) DO UPDATE SET name = excluded.name, dataJson = excluded.dataJson, updatedAt = excluded.updatedAt",
        )
        .bind(&template.id)
        .bind(&template.name)
        .bind(serde_json::to_string(&template)?)
        .bind(format_timestamp(template.created_at))
        .bind(format_timestamp(template.updated_at))
        .execute(self.pool())
        .await?;
        Ok(template)
    }

    pub async fn list_automation_tags(&self) -> Result<Vec<AutomationTag>> {
        let rows = sqlx::query(
            "SELECT id, name, createdAt FROM automationTags ORDER BY name COLLATE NOCASE ASC",
        )
        .fetch_all(self.pool())
        .await?;
        rows.into_iter()
            .map(|row| {
                Ok(AutomationTag {
                    id: row.try_get("id")?,
                    name: row.try_get("name")?,
                    created_at: super::parse_timestamp(&row.try_get::<String, _>("createdAt")?),
                })
            })
            .collect()
    }

    pub async fn upsert_automation_tag(&self, mut tag: AutomationTag) -> Result<AutomationTag> {
        tag.name = tag.name.trim().to_string();
        if tag.name.is_empty() {
            bail!("automation tag name is required");
        }
        if tag.id.trim().is_empty() {
            tag.id = Uuid::new_v4().to_string();
        }
        sqlx::query(
            "INSERT INTO automationTags (id, name, createdAt) VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET name = excluded.name",
        )
        .bind(&tag.id)
        .bind(&tag.name)
        .bind(format_timestamp(tag.created_at))
        .execute(self.pool())
        .await?;
        Ok(tag)
    }

    pub async fn set_automation_tags(&self, automation_id: &str, tag_ids: &[String]) -> Result<()> {
        let mut transaction = self.pool().begin().await?;
        sqlx::query("DELETE FROM automationTagAssignments WHERE automationId = ?")
            .bind(automation_id)
            .execute(&mut *transaction)
            .await?;
        for tag_id in tag_ids {
            sqlx::query(
                "INSERT OR IGNORE INTO automationTagAssignments (automationId, tagId) VALUES (?, ?)",
            )
            .bind(automation_id)
            .bind(tag_id)
            .execute(&mut *transaction)
            .await?;
        }
        transaction.commit().await?;
        Ok(())
    }

    pub async fn set_automation_agent_policy(
        &self,
        policy: AutomationAgentPolicy,
    ) -> Result<AutomationAgentPolicy> {
        sqlx::query(
            "INSERT INTO automationAgentPolicies (profileId, dataJson, updatedAt) VALUES (?, ?, ?) \
             ON CONFLICT(profileId) DO UPDATE SET dataJson = excluded.dataJson, updatedAt = excluded.updatedAt",
        )
        .bind(&policy.profile_id)
        .bind(serde_json::to_string(&policy)?)
        .bind(format_timestamp(policy.updated_at))
        .execute(self.pool())
        .await?;
        Ok(policy)
    }

    pub async fn automation_agent_policy(&self, profile_id: &str) -> Result<AutomationAgentPolicy> {
        let row = sqlx::query("SELECT dataJson FROM automationAgentPolicies WHERE profileId = ?")
            .bind(profile_id)
            .fetch_optional(self.pool())
            .await?;
        Ok(match row {
            Some(row) => {
                let data: String = row.try_get("dataJson")?;
                serde_json::from_str(&data)?
            }
            None => AutomationAgentPolicy {
                profile_id: profile_id.to_string(),
                may_activate_or_edit_active: false,
                may_execute: false,
                updated_at: Utc::now(),
            },
        })
    }

    pub async fn set_automation_project_policy(
        &self,
        policy: AutomationProjectPolicy,
    ) -> Result<AutomationProjectPolicy> {
        sqlx::query(
            "INSERT INTO automationProjectPolicies (projectId, dataJson, updatedAt) VALUES (?, ?, ?) \
             ON CONFLICT(projectId) DO UPDATE SET dataJson = excluded.dataJson, updatedAt = excluded.updatedAt",
        )
        .bind(&policy.project_id)
        .bind(serde_json::to_string(&policy)?)
        .bind(format_timestamp(policy.updated_at))
        .execute(self.pool())
        .await?;
        Ok(policy)
    }

    pub async fn automation_project_policy(
        &self,
        project_id: &str,
    ) -> Result<AutomationProjectPolicy> {
        let row = sqlx::query("SELECT dataJson FROM automationProjectPolicies WHERE projectId = ?")
            .bind(project_id)
            .fetch_optional(self.pool())
            .await?;
        Ok(match row {
            Some(row) => {
                let data: String = row.try_get("dataJson")?;
                serde_json::from_str(&data)?
            }
            None => AutomationProjectPolicy {
                project_id: project_id.to_string(),
                repo_declared: false,
                local_approved: false,
                restrictive: false,
                updated_at: Utc::now(),
            },
        })
    }

    pub async fn export_automation_catalog(&self) -> Result<AutomationExportBundle> {
        let definitions = self.list_automations(false).await?;
        let templates = self.list_automation_templates().await?;
        let tags = self.list_automation_tags().await?;
        let mut project_keys = BTreeMap::new();
        for definition in &definitions {
            if let Some(project_id) = definition.project_id.as_deref() {
                let key = format!("project-{}", project_keys.len());
                project_keys.entry(project_id.to_string()).or_insert(key);
            }
        }
        for template in &templates {
            if let Some(project_id) = template.project_id.as_deref() {
                let key = format!("project-{}", project_keys.len());
                project_keys.entry(project_id.to_string()).or_insert(key);
            }
        }
        let tag_keys = tags
            .iter()
            .enumerate()
            .map(|(index, tag)| (tag.id.clone(), format!("tag-{index}")))
            .collect::<BTreeMap<_, _>>();
        let definitions = definitions
            .into_iter()
            .enumerate()
            .map(|(index, definition)| {
                portable_definition(definition, index, &project_keys, &tag_keys)
            })
            .collect();
        Ok(AutomationExportBundle {
            schema_version: super::AUTOMATION_SCHEMA_VERSION.to_string(),
            definitions,
            templates: templates
                .into_iter()
                .map(|template| portable_template(template, &project_keys, &tag_keys))
                .collect(),
            tags: tags
                .into_iter()
                .enumerate()
                .map(|(index, tag)| portable_tag(tag, index))
                .collect(),
        })
    }

    pub async fn import_automation_catalog(
        &self,
        bundle: AutomationImportBundle,
        remap: &std::collections::BTreeMap<String, String>,
        actor: AutomationActor,
    ) -> Result<Vec<AutomationDefinition>> {
        if bundle.schema_version != super::AUTOMATION_SCHEMA_VERSION {
            bail!(
                "unsupported automation import schema: {}",
                bundle.schema_version
            );
        }
        let mut catalog_remap = remap.clone();
        for tag in &bundle.tags {
            // A catalog import always owns its newly-created tag identity.
            // Never let a caller map an imported tag onto an existing local
            // row and accidentally overwrite its name.
            catalog_remap.insert(tag.id.clone(), Uuid::new_v4().to_string());
        }
        let mut imported_tags = bundle.tags;
        for tag in &mut imported_tags {
            tag.id = catalog_remap
                .get(&tag.id)
                .cloned()
                .ok_or_else(|| anyhow!("import tag remap is missing: {}", tag.id))?;
            self.upsert_automation_tag(tag.clone()).await?;
        }
        let mut imported = Vec::new();
        for mut definition in bundle.definitions {
            remap_definition_target(&mut definition, remap)?;
            remap_definition_catalog_ids(&mut definition, &catalog_remap)?;
            definition.id = Uuid::new_v4().to_string();
            definition.slug = format!("{}-{}", definition.slug, &definition.id[..8]);
            definition.state = AutomationState::Draft;
            definition.revision = 0;
            definition.approved_revision = None;
            definition.created_by = actor.clone();
            definition.modified_by = actor.clone();
            let saved = self.upsert_automation(definition, actor.clone()).await?;
            imported.push(saved);
        }
        for mut template in bundle.templates {
            template.id = Uuid::new_v4().to_string();
            template.created_by = actor.clone();
            if let Some(project_id) = template.project_id.as_mut() {
                *project_id = remap.get(project_id).cloned().ok_or_else(|| {
                    anyhow!("import requires a local remap for project: {project_id}")
                })?;
            }
            template.tag_ids = template
                .tag_ids
                .iter()
                .map(|tag_id| {
                    catalog_remap
                        .get(tag_id)
                        .cloned()
                        .ok_or_else(|| anyhow!("import requires a remap for tag: {tag_id}"))
                })
                .collect::<Result<Vec<_>>>()?;
            self.upsert_automation_template(template).await?;
        }
        Ok(imported)
    }
}

fn portable_definition(
    definition: AutomationDefinition,
    index: usize,
    project_keys: &BTreeMap<String, String>,
    tag_keys: &BTreeMap<String, String>,
) -> Value {
    let mut value =
        serde_json::to_value(&definition).expect("automation definition is serializable");
    if let Some(object) = value.as_object_mut() {
        if let Some(project_id) = object.remove("projectId") {
            if project_id.as_str().is_some_and(|id| !id.trim().is_empty()) {
                object.insert(
                    "projectKey".to_string(),
                    Value::String(
                        project_keys
                            .get(project_id.as_str().unwrap())
                            .cloned()
                            .unwrap_or_else(|| format!("project-{index}")),
                    ),
                );
            }
        }
        let tag_ids = object
            .remove("tagIds")
            .unwrap_or_else(|| Value::Array(vec![]));
        object.insert(
            "tagKeys".to_string(),
            Value::Array(
                tag_ids
                    .as_array()
                    .into_iter()
                    .flatten()
                    .filter_map(Value::as_str)
                    .filter_map(|tag_id| tag_keys.get(tag_id))
                    .cloned()
                    .map(Value::String)
                    .collect(),
            ),
        );
        if let Some(target) = object.get_mut("target").and_then(Value::as_object_mut) {
            if let Some((kind, details)) = target.iter_mut().next() {
                let key_prefix = format!("target-{index}");
                if let Some(details) = details.as_object_mut() {
                    details.remove("workspaceId");
                    details.remove("tabId");
                    let conversation_id = details.remove("conversationId");
                    details.remove("agentProfileId");
                    match kind.as_str() {
                        "existingTab" => {
                            details.insert(
                                "workspaceKey".to_string(),
                                Value::String(format!("{key_prefix}-workspace")),
                            );
                            details.insert(
                                "tabKey".to_string(),
                                Value::String(format!("{key_prefix}-tab")),
                            );
                            if conversation_id
                                .as_ref()
                                .and_then(Value::as_str)
                                .is_some_and(|value| !value.trim().is_empty())
                            {
                                details.insert(
                                    "conversationKey".to_string(),
                                    Value::String(format!("{key_prefix}-conversation")),
                                );
                            }
                        }
                        "freshTab" => {
                            details.insert(
                                "workspaceKey".to_string(),
                                Value::String(format!("{key_prefix}-workspace")),
                            );
                            details.insert(
                                "profileKey".to_string(),
                                Value::String(format!("{key_prefix}-profile")),
                            );
                        }
                        "managedWorkspace" => {
                            details.insert(
                                "sourceWorkspaceKey".to_string(),
                                Value::String(format!("{key_prefix}-workspace")),
                            );
                            details.insert(
                                "profileKey".to_string(),
                                Value::String(format!("{key_prefix}-profile")),
                            );
                        }
                        _ => {}
                    }
                }
            }
        }
    }
    value
}

fn portable_template(
    template: AutomationTemplate,
    project_keys: &BTreeMap<String, String>,
    tag_keys: &BTreeMap<String, String>,
) -> Value {
    let mut value = serde_json::to_value(template).expect("automation template is serializable");
    if let Some(object) = value.as_object_mut() {
        object.remove("id");
        object.remove("createdBy");
        if let Some(project_id) = object.remove("projectId") {
            if let Some(project_id) = project_id.as_str().filter(|id| !id.trim().is_empty()) {
                if let Some(project_key) = project_keys.get(project_id) {
                    object.insert("projectKey".to_string(), Value::String(project_key.clone()));
                }
            }
        }
        let tag_ids = object
            .remove("tagIds")
            .unwrap_or_else(|| Value::Array(vec![]));
        object.insert(
            "tagKeys".to_string(),
            Value::Array(
                tag_ids
                    .as_array()
                    .into_iter()
                    .flatten()
                    .filter_map(Value::as_str)
                    .filter_map(|tag_id| tag_keys.get(tag_id))
                    .cloned()
                    .map(Value::String)
                    .collect(),
            ),
        );
    }
    value
}

fn portable_tag(tag: AutomationTag, index: usize) -> Value {
    let mut value = serde_json::to_value(tag).expect("automation tag is serializable");
    if let Some(object) = value.as_object_mut() {
        object.remove("id");
        object.insert("tagKey".to_string(), Value::String(format!("tag-{index}")));
    }
    value
}

fn remap_definition_catalog_ids(
    definition: &mut AutomationDefinition,
    remap: &std::collections::BTreeMap<String, String>,
) -> Result<()> {
    if let Some(project_id) = definition.project_id.as_mut() {
        *project_id = remap
            .get(project_id)
            .cloned()
            .ok_or_else(|| anyhow!("import requires a local remap for project: {project_id}"))?;
    }
    definition.tag_ids = definition
        .tag_ids
        .iter()
        .map(|tag_id| {
            remap
                .get(tag_id)
                .cloned()
                .ok_or_else(|| anyhow!("import requires a remap for tag: {tag_id}"))
        })
        .collect::<Result<Vec<_>>>()?;
    Ok(())
}

fn remap_definition_target(
    definition: &mut AutomationDefinition,
    remap: &std::collections::BTreeMap<String, String>,
) -> Result<()> {
    let source = match &definition.target {
        super::AutomationTarget::ExistingTab { workspace_id, .. }
        | super::AutomationTarget::FreshTab { workspace_id, .. } => workspace_id,
        super::AutomationTarget::ManagedWorkspace {
            source_workspace_id,
            ..
        } => source_workspace_id,
    };
    let mapped = remap
        .get(source)
        .ok_or_else(|| anyhow!("import requires a local remap for target: {source}"))?
        .clone();
    match &mut definition.target {
        super::AutomationTarget::ExistingTab { workspace_id, .. }
        | super::AutomationTarget::FreshTab { workspace_id, .. } => *workspace_id = mapped,
        super::AutomationTarget::ManagedWorkspace {
            source_workspace_id,
            ..
        } => *source_workspace_id = mapped,
    }
    Ok(())
}
