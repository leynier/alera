#[path = "automation_catalog_import.rs"]
mod catalog_import;
use catalog_import::normalize_portable_import;

use alera_core::runtime::{AutomationActor, AutomationImportBundle, AutomationTemplate};
use chrono::Utc;
use serde_json::{json, Map, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::ServerActor;

impl ServerActor {
    pub(super) async fn automation_templates_request(&self, payload: &Value) -> HostResult<Value> {
        if let Some(value) = payload.get("template") {
            let template = decode_automation_template(value)?;
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
            .has_pending_automation_work()
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

fn decode_automation_template(value: &Value) -> HostResult<AutomationTemplate> {
    let mut object = value
        .as_object()
        .cloned()
        .ok_or_else(|| HostError::format("automation template must be a JSON object"))?;
    fill_timestamp(&mut object, "updatedAt");
    serde_json::from_value(Value::Object(object))
        .map_err(|error| HostError::format(format!("invalid automation template: {error}")))
}

fn fill_timestamp(object: &mut Map<String, Value>, key: &str) {
    object
        .entry(key.to_string())
        .or_insert_with(|| json!(Utc::now()));
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    #[test]
    fn project_checkout_import_requires_project_host_and_profile_remaps() {
        let bundle = serde_json::json!({"definitions":[{"target":{"projectCheckout": {
            "projectKey":"project-key", "hostKey":"host-key", "profileKey":"profile-key"
        }}}]});
        let missing_host = BTreeMap::from([
            ("project-key".into(), "project".into()),
            ("profile-key".into(), "profile".into()),
        ]);
        assert!(normalize_portable_import(bundle.clone(), &missing_host).is_err());
        let mut remap = missing_host;
        remap.insert("host-key".into(), "ssh-host".into());
        let decoded = normalize_portable_import(bundle, &remap).unwrap();
        assert_eq!(
            decoded["definitions"][0]["target"]["projectCheckout"],
            serde_json::json!({
                "projectId":"project", "hostId":"ssh-host", "agentProfileId":"profile"
            })
        );
    }

    use super::{decode_automation_template, normalize_portable_import};
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

    #[test]
    fn template_upsert_payload_accepts_missing_updated_at() {
        let template = decode_automation_template(&json!({
            "id": "t",
            "name": "T",
            "promptTemplate": "ping",
            "createdAt": "2026-09-08T00:00:00Z",
            "createdBy": {"kind": "localCli"}
        }))
        .unwrap();
        assert_eq!(template.id, "t");
        assert_eq!(template.name, "T");
        assert_eq!(template.prompt_template, "ping");
        assert!(template.updated_at.timestamp() > 0);
    }

    #[test]
    fn template_upsert_payload_keeps_supplied_updated_at() {
        let template = decode_automation_template(&json!({
            "id": "t",
            "name": "T",
            "promptTemplate": "ping",
            "createdAt": "2026-09-08T00:00:00Z",
            "updatedAt": "2026-01-02T03:04:05Z",
            "createdBy": {"kind": "localCli"}
        }))
        .unwrap();
        assert_eq!(
            template.updated_at,
            "2026-01-02T03:04:05Z"
                .parse::<chrono::DateTime<chrono::Utc>>()
                .unwrap()
        );
    }
}
