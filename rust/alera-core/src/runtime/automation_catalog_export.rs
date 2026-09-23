use crate::runtime::{AutomationDefinition, AutomationTemplate};
use serde_json::Value;
use std::collections::BTreeMap;

pub(super) fn portable_definition(
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
                        "projectCheckout" => {
                            details.remove("projectId");
                            details.remove("hostId");
                            for (key, suffix) in [
                                ("projectKey", "project"),
                                ("hostKey", "host"),
                                ("profileKey", "profile"),
                            ] {
                                details.insert(
                                    key.into(),
                                    Value::String(format!("{key_prefix}-{suffix}")),
                                );
                            }
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

pub(super) fn portable_template(
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
