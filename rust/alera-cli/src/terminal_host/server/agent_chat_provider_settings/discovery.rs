//! Verified SDK listings and existing AI Assist CLI parsers, without inference.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::time::Duration;

use alera_agent_http::{HttpClientConfig, ReqwestTransport};
use serde_json::{json, Value};

use super::probe::{ProbeCommand, ProviderProbe};

const SDK_TIMEOUT: Duration = Duration::from_secs(8);
const MAX_MODELS: usize = 500;

pub(crate) async fn cli_models(
    provider: &str,
    executable: &Path,
    environment: &BTreeMap<String, String>,
    cwd: Option<PathBuf>,
    probe: &dyn ProviderProbe,
) -> Option<Result<Vec<Value>, String>> {
    let args = match provider {
        "codex" => vec!["debug", "models"],
        "pi" => vec!["--list-models"],
        "antigravity" => vec!["models"],
        // These adapters have no verified session-free listing command.
        _ => return None,
    };
    let output = match probe
        .run(ProbeCommand {
            executable: executable.into(),
            args: args.into_iter().map(str::to_owned).collect(),
            environment: environment.clone(),
            cwd,
        })
        .await
    {
        Ok(output) if output.success => output.stdout,
        _ => return Some(Err("Model listing failed.".into())),
    };
    Some(parse_cli(provider, &output))
}

pub(crate) fn parse_cli(provider: &str, output: &str) -> Result<Vec<Value>, String> {
    let mut models = Vec::new();
    match provider {
        "codex" => {
            let raw: Value =
                serde_json::from_str(output).map_err(|_| "Invalid Codex model listing.")?;
            let entries = raw
                .get("models")
                .or_else(|| raw.get("data"))
                .and_then(Value::as_array)
                .ok_or("Invalid Codex model listing.")?;
            for entry in entries.iter().take(MAX_MODELS) {
                let Some(id) = entry
                    .get("slug")
                    .or_else(|| entry.get("model"))
                    .or_else(|| entry.get("id"))
                    .and_then(Value::as_str)
                else {
                    continue;
                };
                let mut model = json!({"id":id,"label":entry.get("display_name").or_else(|| entry.get("displayName")).and_then(Value::as_str).unwrap_or(id),"source":"discovered"});
                let efforts: Vec<Value> = entry
                    .get("supported_reasoning_levels")
                    .or_else(|| entry.get("supportedReasoningEfforts"))
                    .and_then(Value::as_array)
                    .into_iter()
                    .flatten()
                    .filter_map(|value| {
                        value.as_str().or_else(|| {
                            value
                                .get("effort")
                                .or_else(|| value.get("reasoningEffort"))
                                .and_then(Value::as_str)
                        })
                    })
                    .filter(|value| {
                        matches!(
                            *value,
                            "none"
                                | "minimal"
                                | "low"
                                | "medium"
                                | "high"
                                | "xhigh"
                                | "max"
                                | "ultra"
                        )
                    })
                    .map(|effort| json!(effort))
                    .collect();
                if !efforts.is_empty() {
                    if let Some(default) = entry
                        .get("default_reasoning_level")
                        .or_else(|| entry.get("defaultReasoningEffort"))
                        .and_then(Value::as_str)
                    {
                        if efforts
                            .iter()
                            .any(|effort| effort.as_str() == Some(default))
                        {
                            model["defaultReasoningEffort"] = json!(default);
                        }
                    }
                    model["reasoningEfforts"] = json!(efforts);
                }
                model["providerDefault"] = json!(entry
                    .get("isDefault")
                    .and_then(Value::as_bool)
                    .unwrap_or(false));
                models.push(model);
            }
        }
        "pi" => {
            for line in output.lines().take(MAX_MODELS + 1) {
                let columns: Vec<&str> = line.split_whitespace().collect();
                if columns.len() >= 2 && columns[0] != "provider" && !columns[0].starts_with('-') {
                    let id = format!("{}/{}", columns[0], columns[1]);
                    models.push(json!({"id":id,"label":id,"source":"discovered"}));
                }
            }
        }
        "antigravity" => {
            for line in output.lines().take(MAX_MODELS + 1) {
                let id = line.trim().trim_start_matches(['*', '-']).trim();
                if !id.is_empty() && !id.to_lowercase().starts_with("available model") {
                    models.push(json!({"id":id,"label":id,"source":"discovered"}));
                }
            }
        }
        _ => return Err("This provider has no verified model listing.".into()),
    }
    let mut seen = std::collections::HashSet::new();
    models.retain(|model| {
        model["id"]
            .as_str()
            .is_some_and(|id| !id.trim().is_empty() && seen.insert(id.to_owned()))
    });
    Ok(models)
}

pub(crate) async fn opencode(
    mut config: alera_provider_opencode::OpenCodeProviderConfig,
) -> Result<Vec<Value>, String> {
    config.request_timeout = SDK_TIMEOUT;
    config.max_sse_event_bytes = 1024 * 1024;
    let mut child = if config.server_url.is_none() {
        let mut server_config = config.local_server_config();
        server_config.port = 0;
        server_config.startup_timeout = SDK_TIMEOUT;
        let server = opencode_agent_sdk::OpenCodeServer::spawn(server_config)
            .await
            .map_err(|_| "OpenCode model discovery could not start.")?;
        config.server_url = Some(server.url().into());
        config.server_password = server.password().map(str::to_owned);
        Some(server)
    } else {
        None
    };
    let result = async {
        let transport = ReqwestTransport::new(HttpClientConfig { base_url:config.server_url.clone().expect("resolved server"),request_timeout:SDK_TIMEOUT,max_response_bytes:1024 * 1024,..Default::default() })
            .map_err(|_| "Invalid OpenCode model endpoint.")?;
        let mut client = opencode_agent_sdk::OpenCodeClient::new(transport,config.client_config());
        let models = client.list_models().await.map_err(|_| "OpenCode model listing failed.")?;
        Ok(models.into_iter().take(MAX_MODELS).map(|model| json!({"id":format!("{}/{}",model.provider_id,model.model_id),"label":model.name.unwrap_or(model.model_id),"source":"discovered"})).collect())
    }.await;
    if let Some(child) = &mut child {
        let _ = child.close().await;
    }
    result.map_err(str::to_owned)
}

pub(crate) async fn cursor(
    config: alera_provider_cursor::CursorProviderConfig,
    bridge: Option<cursor_agent_sdk::CursorBridgeConfig>,
) -> Result<Vec<Value>, String> {
    let mut child = if let Some(mut bridge) = bridge {
        bridge.startup_timeout = SDK_TIMEOUT;
        bridge.client_timeout = SDK_TIMEOUT;
        Some(
            cursor_agent_sdk::CursorBridge::spawn(bridge)
                .await
                .map_err(|_| "Cursor model discovery could not start.")?,
        )
    } else {
        None
    };
    let result = async {
        let client = match &child {
            Some(child) => child.client().clone(),
            None => { let mut client = config.client_config(); client.timeout = SDK_TIMEOUT; cursor_agent_sdk::CursorClient::connect(client).map_err(|_| "Invalid Cursor model endpoint.")? },
        };
        let key = config.api_key.as_deref().ok_or("Cursor model discovery requires a declared API key.")?;
        let raw = client.list_models(key).await.map_err(|_| "Cursor model listing failed.")?;
        let entries = raw.get("models").or_else(|| raw.get("data")).and_then(Value::as_array).ok_or("Invalid Cursor model listing.")?;
        Ok(entries.iter().take(MAX_MODELS).filter_map(|raw| {
            let model: cursor_agent_sdk::SdkModel = serde_json::from_value(raw.clone()).ok()?;
            let efforts = alera_provider_cursor::model_reasoning_efforts(&model);
            let mut entry = json!({"id":model.id,"label":if model.display_name.is_empty() { &model.id } else { &model.display_name },"source":"discovered"});
            if !efforts.is_empty() {
                entry["reasoningEfforts"] = json!(efforts);
                if let Some(default) = alera_provider_cursor::default_model_reasoning_effort(&model) { entry["defaultReasoningEffort"] = json!(default); }
            }
            Some(entry)
        }).collect())
    }.await;
    if let Some(child) = &mut child {
        let _ = child.close().await;
    }
    result.map_err(str::to_owned)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn codex_efforts_come_only_from_exact_metadata() {
        let models = parse_cli("codex",r#"{"models":[{"slug":"verified","display_name":"Verified","supported_reasoning_levels":[{"effort":"high"}],"default_reasoning_level":"high"},{"slug":"custom","display_name":"Custom"}]}"#).unwrap();
        assert_eq!(models[0]["reasoningEfforts"], json!(["high"]));
        assert!(models[1].get("reasoningEfforts").is_none());
    }
    #[test]
    fn ported_cli_parsers_deduplicate_and_skip_headers() {
        assert_eq!(
            parse_cli("pi", "provider model\nopenai test 128k\nopenai test 128k")
                .unwrap()
                .len(),
            1
        );
        assert_eq!(
            parse_cli(
                "antigravity",
                "Available models\n* gemini-test\n- gemini-test"
            )
            .unwrap()[0]["id"],
            "gemini-test"
        );
    }
}
