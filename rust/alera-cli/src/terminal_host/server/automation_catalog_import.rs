use crate::terminal_host::host_error::{HostError, HostResult};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use uuid::Uuid;

pub(super) fn normalize_portable_import(
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
                "projectCheckout" => {
                    for (key, field, kind) in [
                        ("projectKey", "projectId", "project"),
                        ("hostKey", "hostId", "host"),
                    ] {
                        if let Some(key) = details
                            .remove(key)
                            .and_then(|value| value.as_str().map(str::to_string))
                        {
                            details.insert(
                                field.into(),
                                Value::String(remap_value(remap, &key, kind)?),
                            );
                        }
                    }
                    if let Some(profile_key) = profile_key {
                        details.insert(
                            "agentProfileId".into(),
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
