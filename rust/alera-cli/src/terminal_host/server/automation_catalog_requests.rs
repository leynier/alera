use alera_core::runtime::{AutomationActor, AutomationImportBundle};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use uuid::Uuid;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::ServerActor;

impl ServerActor {
    pub(super) async fn automation_templates_request(&self, payload: &Value) -> HostResult<Value> {
        if let Some(value) = payload.get("template") {
            let template = serde_json::from_value(value.clone()).map_err(|error| {
                HostError::format(format!("invalid automation template: {error}"))
            })?;
            let saved = self
                .runtime_store
                .upsert_automation_template(template)
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
            return serde_json::to_value(saved)
                .map_err(|error| HostError::state(error.to_string()));
        }
        Ok(json!({
            "items": self.runtime_store.list_automation_templates().await.map_err(|error| HostError::state(error.to_string()))?,
        }))
    }

    pub(super) async fn automation_tags_request(
        &self,
        client_id: u64,
        payload: &Value,
        actor: AutomationActor,
    ) -> HostResult<Value> {
        if let Some(value) = payload.get("tag") {
            let tag = serde_json::from_value(value.clone())
                .map_err(|error| HostError::format(format!("invalid automation tag: {error}")))?;
            let saved = self
                .runtime_store
                .upsert_automation_tag(tag)
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
            return serde_json::to_value(saved)
                .map_err(|error| HostError::state(error.to_string()));
        }
        if let (Some(automation_id), Some(tag_ids)) = (
            payload.get("automationId").and_then(Value::as_str),
            payload.get("tagIds").and_then(Value::as_array),
        ) {
            let actor = self.resolve_policy_actor(client_id, payload, actor).await?;
            let definition = self
                .runtime_store
                .find_automation(automation_id)
                .await
                .map_err(|error| HostError::state(error.to_string()))?
                .ok_or_else(|| {
                    HostError::state(format!("automation not found: {automation_id}"))
                })?;
            self.ensure_agent_policy(&definition, &actor, false).await?;
            let tag_ids = tag_ids
                .iter()
                .map(|value| value.as_str().map(str::to_string))
                .collect::<Option<Vec<_>>>()
                .ok_or_else(|| HostError::format("automation tag ids must be strings"))?;
            self.runtime_store
                .set_automation_tags(automation_id, &tag_ids)
                .await
                .map_err(|error| HostError::state(error.to_string()))?;
            return Ok(json!({"automationId": automation_id, "tagIds": tag_ids}));
        }
        Ok(json!({
            "items": self.runtime_store.list_automation_tags().await.map_err(|error| HostError::state(error.to_string()))?,
        }))
    }

    pub(super) async fn automation_export_request(
        &self,
        actor: AutomationActor,
    ) -> HostResult<Value> {
        let bundle = self
            .runtime_store
            .export_automation_catalog()
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.runtime_store
            .insert_automation_audit_event(
                None,
                None,
                "export",
                actor,
                None,
                json!({ "schemaVersion": bundle.schema_version }),
            )
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        serde_json::to_value(bundle).map_err(|error| HostError::state(error.to_string()))
    }

    pub(super) async fn automation_import_request(
        &mut self,
        payload: &Value,
        actor: AutomationActor,
    ) -> HostResult<Value> {
        let bundle_value = payload
            .get("bundle")
            .cloned()
            .unwrap_or_else(|| payload.clone());
        let remap = payload.get("remap").cloned().unwrap_or_else(|| json!({}));
        let mut remap: std::collections::BTreeMap<String, String> =
            serde_json::from_value(remap)
                .map_err(|error| HostError::format(format!("invalid automation remap: {error}")))?;
        let bundle_value = normalize_portable_import(bundle_value, &remap)?;
        // Portable keys have already been resolved to local ids. Preserve
        // those ids through the store's legacy remap path as identity maps.
        for value in remap.values().cloned().collect::<Vec<_>>() {
            remap.entry(value.clone()).or_insert(value);
        }
        let bundle: AutomationImportBundle = serde_json::from_value(bundle_value)
            .map_err(|error| HostError::format(format!("invalid automation catalog: {error}")))?;
        let imported = self
            .runtime_store
            .import_automation_catalog(bundle, &remap, actor.clone())
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.runtime_store
            .insert_automation_audit_event(
                None,
                None,
                "import",
                actor,
                None,
                json!({ "count": imported.len(), "remap": remap }),
            )
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.automations_active = self
            .runtime_store
            .has_active_automations()
            .await
            .map_err(|error| HostError::state(error.to_string()))?;
        self.automation_wake.notify_one();
        self.broadcast_authenticated(crate::terminal_host::protocol::event(
            "automationsChanged",
            json!({}),
        ));
        Ok(json!({"items": imported}))
    }
}

fn normalize_portable_import(
    mut bundle: Value,
    remap: &std::collections::BTreeMap<String, String>,
) -> HostResult<Value> {
    let tag_ids = normalize_portable_tags(&mut bundle)?;
    if let Some(definitions) = bundle.get_mut("definitions").and_then(Value::as_array_mut) {
        for definition in definitions {
            let Some(object) = definition.as_object_mut() else {
                return Err(HostError::format("automation definition must be an object"));
            };
            if let Some(project_key) = object
                .remove("projectKey")
                .and_then(|value| value.as_str().map(str::to_string))
            {
                object.insert(
                    "projectId".to_string(),
                    Value::String(remap_value(remap, &project_key, "project")?),
                );
            }
            if let Some(tag_keys) = object.remove("tagKeys") {
                object.insert(
                    "tagIds".to_string(),
                    Value::Array(
                        tag_keys
                            .as_array()
                            .ok_or_else(|| {
                                HostError::format("automation tagKeys must be an array")
                            })?
                            .iter()
                            .map(|value| {
                                let key = value.as_str().ok_or_else(|| {
                                    HostError::format("automation tagKeys must contain strings")
                                })?;
                                tag_ids.get(key).cloned().ok_or_else(|| {
                                    HostError::format(format!(
                                        "import requires a local remap for tag: {key}"
                                    ))
                                })
                            })
                            .collect::<HostResult<Vec<_>>>()?
                            .into_iter()
                            .map(Value::String)
                            .collect(),
                    ),
                );
            }
            let Some(target) = object.get_mut("target").and_then(Value::as_object_mut) else {
                continue;
            };
            let Some((kind, details)) = target.iter_mut().next() else {
                continue;
            };
            let Some(details) = details.as_object_mut() else {
                continue;
            };
            let workspace_key = details
                .remove("workspaceKey")
                .and_then(|value| value.as_str().map(str::to_string));
            let source_workspace_key = details
                .remove("sourceWorkspaceKey")
                .and_then(|value| value.as_str().map(str::to_string));
            let tab_key = details
                .remove("tabKey")
                .and_then(|value| value.as_str().map(str::to_string));
            let profile_key = details
                .remove("profileKey")
                .and_then(|value| value.as_str().map(str::to_string));
            let conversation_key = details
                .remove("conversationKey")
                .and_then(|value| value.as_str().map(str::to_string));
            match kind.as_str() {
                "existingTab" => {
                    if let Some(workspace_key) = workspace_key {
                        details.insert(
                            "workspaceId".to_string(),
                            Value::String(remap_value(remap, &workspace_key, "workspace")?),
                        );
                    }
                    if let Some(tab_key) = tab_key {
                        details.insert(
                            "tabId".to_string(),
                            Value::String(remap_value(remap, &tab_key, "tab")?),
                        );
                    }
                    if let Some(conversation_key) = conversation_key {
                        details.insert(
                            "conversationId".to_string(),
                            Value::String(remap_value(remap, &conversation_key, "conversation")?),
                        );
                    }
                }
                "freshTab" => {
                    if let Some(workspace_key) = workspace_key {
                        details.insert(
                            "workspaceId".to_string(),
                            Value::String(remap_value(remap, &workspace_key, "workspace")?),
                        );
                    }
                    if let Some(profile_key) = profile_key {
                        details.insert(
                            "agentProfileId".to_string(),
                            Value::String(remap_value(remap, &profile_key, "profile")?),
                        );
                    }
                }
                "managedWorkspace" => {
                    if let Some(workspace_key) = source_workspace_key {
                        details.insert(
                            "sourceWorkspaceId".to_string(),
                            Value::String(remap_value(remap, &workspace_key, "workspace")?),
                        );
                    }
                    if let Some(profile_key) = profile_key {
                        details.insert(
                            "agentProfileId".to_string(),
                            Value::String(remap_value(remap, &profile_key, "profile")?),
                        );
                    }
                }
                _ => {}
            }
        }
    }
    if let Some(templates) = bundle.get_mut("templates").and_then(Value::as_array_mut) {
        for template in templates {
            let object = template
                .as_object_mut()
                .ok_or_else(|| HostError::format("automation template must be an object"))?;
            object
                .entry("id")
                .or_insert_with(|| Value::String(Uuid::new_v4().to_string()));
            object
                .entry("createdBy")
                .or_insert_with(|| json!({"kind": "humanDesktop"}));
            if let Some(project_key) = object
                .remove("projectKey")
                .and_then(|value| value.as_str().map(str::to_string))
            {
                object.insert(
                    "projectId".to_string(),
                    Value::String(remap_value(remap, &project_key, "project")?),
                );
            }
            if let Some(tag_keys) = object.remove("tagKeys") {
                object.insert(
                    "tagIds".to_string(),
                    Value::Array(
                        tag_keys
                            .as_array()
                            .ok_or_else(|| {
                                HostError::format("automation tagKeys must be an array")
                            })?
                            .iter()
                            .map(|value| {
                                let key = value.as_str().ok_or_else(|| {
                                    HostError::format("automation tagKeys must contain strings")
                                })?;
                                tag_ids.get(key).cloned().ok_or_else(|| {
                                    HostError::format(format!(
                                        "import requires a local remap for tag: {key}"
                                    ))
                                })
                            })
                            .collect::<HostResult<Vec<_>>>()?
                            .into_iter()
                            .map(Value::String)
                            .collect(),
                    ),
                );
            }
        }
    }
    Ok(bundle)
}

fn normalize_portable_tags(bundle: &mut Value) -> HostResult<BTreeMap<String, String>> {
    let mut tag_ids = BTreeMap::new();
    let Some(tags) = bundle.get_mut("tags").and_then(Value::as_array_mut) else {
        return Ok(tag_ids);
    };
    for tag in tags {
        let object = tag
            .as_object_mut()
            .ok_or_else(|| HostError::format("automation tag must be an object"))?;
        let source_id = object
            .get("id")
            .and_then(Value::as_str)
            .filter(|value| !value.trim().is_empty())
            .map(str::to_string)
            .unwrap_or_else(|| Uuid::new_v4().to_string());
        let key = object
            .remove("tagKey")
            .and_then(|value| value.as_str().map(str::to_string))
            .unwrap_or_else(|| source_id.clone());
        object.insert("id".to_string(), Value::String(source_id.clone()));
        tag_ids.insert(key, source_id.clone());
        tag_ids.insert(source_id.clone(), source_id);
    }
    Ok(tag_ids)
}

fn remap_value(
    remap: &std::collections::BTreeMap<String, String>,
    key: &str,
    kind: &str,
) -> HostResult<String> {
    remap
        .get(key)
        .map(|value| value.trim())
        .filter(|value| !value.is_empty())
        .map(str::to_string)
        .ok_or_else(|| {
            HostError::format(format!("import requires a local remap for {kind}: {key}"))
        })
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::normalize_portable_import;
    use serde_json::json;

    #[test]
    fn portable_import_requires_explicit_target_remaps() {
        let bundle = json!({
            "schemaVersion": "1",
            "definitions": [{
                "projectKey": "project-0",
                "target": {"freshTab": {
                    "workspaceKey": "target-0-workspace",
                    "profileKey": "target-0-profile"
                }}
            }]
        });
        let remap = BTreeMap::from([
            ("project-0".into(), "project".into()),
            ("target-0-workspace".into(), "workspace".into()),
            ("target-0-profile".into(), "profile".into()),
        ]);
        let missing_remaps = bundle.clone();
        let normalized = normalize_portable_import(bundle, &remap).unwrap();
        assert_eq!(normalized["definitions"][0]["projectId"], "project");
        assert_eq!(
            normalized["definitions"][0]["target"]["freshTab"]["workspaceId"],
            "workspace"
        );
        assert!(normalize_portable_import(missing_remaps, &BTreeMap::new()).is_err());
    }

    #[test]
    fn portable_import_rehydrates_project_and_tag_keys_without_local_ids() {
        let bundle = json!({
            "schemaVersion": "1",
            "definitions": [{
                "projectKey": "project-0",
                "tagKeys": ["tag-0"],
                "target": {"freshTab": {
                    "workspaceKey": "target-0-workspace",
                    "profileKey": "target-0-profile"
                }}
            }],
            "templates": [{
                "name": "review",
                "projectKey": "project-0",
                "tagKeys": ["tag-0"]
            }],
            "tags": [{
                "tagKey": "tag-0",
                "name": "review",
                "createdAt": "2026-08-03T00:00:00Z"
            }]
        });
        let remap = BTreeMap::from([
            ("project-0".into(), "project".into()),
            ("target-0-workspace".into(), "workspace".into()),
            ("target-0-profile".into(), "profile".into()),
        ]);
        let normalized = normalize_portable_import(bundle, &remap).unwrap();
        let tag_id = normalized["tags"][0]["id"].as_str().unwrap();
        assert!(!tag_id.is_empty());
        assert_eq!(normalized["definitions"][0]["tagIds"][0], tag_id);
        assert_eq!(normalized["templates"][0]["tagIds"][0], tag_id);
        assert_eq!(normalized["templates"][0]["projectId"], "project");
        assert!(normalized["definitions"][0].get("tagKeys").is_none());
    }
}
