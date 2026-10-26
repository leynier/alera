//! OpenCode skills as T3 Code's driver and adapters read and invoke them: a
//! workspace listing from the server API before a session, and on 2.x the
//! `$name` mentions of a prompt named in its `skills` field. The prompt text
//! is sent unchanged on both generations.

use crate::config::{OpenCodeGeneration, OpenCodeProviderConfig};
use crate::provider::OpenCodeProvider;
use alera_provider_protocol::{skill_mentions, ProviderSkill, ProviderSkillsUpdate};
use opencode_agent_sdk::{
    Generation, HttpClientConfig, HttpTransport, OpenCodeClient, OpenCodeServer, ReqwestTransport,
};
use serde_json::Value;
use std::collections::HashSet;
use std::time::Duration;

/// T3 Code's bound on a workspace listing.
const DISCOVERY_TIMEOUT: Duration = Duration::from_secs(20);
/// How long a 2.x server may take to scan a directory it has not served.
const SCAN_TIMEOUT: Duration = Duration::from_secs(10);
/// How long a prompt waits for the skill list before sending without skills.
const INVENTORY_TIMEOUT: Duration = Duration::from_secs(5);
const MAX_RESPONSE_BYTES: usize = 8 * 1024 * 1024;

/// The skills OpenCode loads for the configured workspace (`directory`, else
/// `cwd`), read from the configured server or from a short-lived local one.
pub async fn discover_skills(
    config: &OpenCodeProviderConfig,
) -> Result<Vec<ProviderSkill>, String> {
    tokio::time::timeout(DISCOVERY_TIMEOUT, discover(config.clone()))
        .await
        .map_err(|_| "OpenCode skill discovery timed out.".to_owned())?
}

async fn discover(mut config: OpenCodeProviderConfig) -> Result<Vec<ProviderSkill>, String> {
    let mut server = None;
    if config.server_url.is_none() {
        let mut server_config = config.local_server_config();
        server_config.port = 0;
        let spawned = OpenCodeServer::spawn(server_config)
            .await
            .map_err(|error| format!("OpenCode skill discovery could not start: {error}"))?;
        config.server_url = Some(spawned.url().to_owned());
        config.server_password = spawned.password().map(str::to_owned);
        server = Some(spawned);
    }
    let result = async {
        let mut client_config = config.client_config();
        client_config.directory = config
            .directory
            .as_ref()
            .or(config.cwd.as_ref())
            .map(|directory| directory.to_string_lossy().into_owned());
        let transport = ReqwestTransport::new(HttpClientConfig {
            base_url: client_config.base_url.clone(),
            request_timeout: config.request_timeout.min(DISCOVERY_TIMEOUT),
            max_response_bytes: MAX_RESPONSE_BYTES,
            ..Default::default()
        })
        .map_err(|error| format!("Invalid OpenCode server address: {error}"))?;
        let mut client = OpenCodeClient::new(transport, client_config);
        let skills = discover_skills_with_client(&mut client).await;
        let _ = client.close().await;
        skills
    }
    .await;
    if let Some(server) = server.as_mut() {
        let _ = server.close().await;
    }
    result
}

/// [discover_skills] over an existing client, scoped to its directory.
pub async fn discover_skills_with_client<T: HttpTransport>(
    client: &mut OpenCodeClient<T>,
) -> Result<Vec<ProviderSkill>, String> {
    let failed = |error: opencode_agent_sdk::OpenCodeError| {
        format!("OpenCode skill listing failed: {error}")
    };
    if client.config().generation == Generation::Legacy1 {
        return Ok(legacy_skills(&client.list_skills().await.map_err(failed)?));
    }
    // A 2.x server scans a directory it has not served in the background:
    // its first read lists no commands, not even the builtins, and
    // `command.updated` plus `skill.updated` for the directory end the scan.
    // Listening must start before the read, since the read starts the scan.
    let listening = client.start_events().await.is_ok();
    let skills = client.list_skills().await.map_err(failed)?;
    if !client.list_commands().await.map_err(failed)?.is_empty() {
        return Ok(v2_skills(&skills));
    }
    if listening {
        let _ = tokio::time::timeout(SCAN_TIMEOUT, scanned(client)).await;
    }
    Ok(v2_skills(&client.list_skills().await.map_err(failed)?))
}

async fn scanned<T: HttpTransport>(client: &mut OpenCodeClient<T>) {
    let directory = client.config().directory.clone();
    let mut pending: HashSet<&str> = ["command.updated", "skill.updated"].into();
    while let Ok(Some(event)) = client.next_raw_event().await {
        let location = event
            .get("location")
            .or_else(|| event.pointer("/data/location"))
            .or_else(|| event.pointer("/properties/location"));
        let here = match &directory {
            Some(directory) => {
                location
                    .and_then(|location| location.get("directory"))
                    .and_then(Value::as_str)
                    == Some(directory.as_str())
            }
            None => location.is_some(),
        };
        let kind = event
            .get("type")
            .and_then(Value::as_str)
            .unwrap_or_default();
        if here && pending.remove(kind) && pending.is_empty() {
            return;
        }
    }
}

fn text<'a>(entry: &'a Value, key: &str) -> Option<&'a str> {
    entry
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
}

/// T3 Code shows a skill's description as its short description too.
fn described(skill: ProviderSkill, entry: &Value) -> ProviderSkill {
    let description = text(entry, "description");
    skill
        .with_description(description)
        .with_short_description(description)
}

fn sorted(skills: Vec<ProviderSkill>) -> Vec<ProviderSkill> {
    let mut skills = ProviderSkillsUpdate::new(skills).skills;
    skills.sort_by(|left, right| {
        left.name
            .to_lowercase()
            .cmp(&right.name.to_lowercase())
            .then_with(|| left.name.cmp(&right.name))
    });
    skills
}

/// 1.x entries: `name`, `description` and the `location` of the file.
fn legacy_skills(entries: &[Value]) -> Vec<ProviderSkill> {
    sorted(
        entries
            .iter()
            .filter_map(|entry| {
                let skill = ProviderSkill::from_native(
                    text(entry, "name")?,
                    text(entry, "location")?,
                    true,
                )?;
                Some(described(skill, entry))
            })
            .collect(),
    )
}

/// 2.x entries: the `id` a prompt names, a display `name`, and the `path`.
fn v2_skills(entries: &[Value]) -> Vec<ProviderSkill> {
    sorted(
        entries
            .iter()
            .filter_map(|entry| {
                let id = entry.get("id").and_then(Value::as_str)?;
                let path = entry.get("path").and_then(Value::as_str)?;
                let name = entry.get("name").and_then(Value::as_str);
                let skill = ProviderSkill::from_native(id, path, true)?
                    .with_display_name(name.filter(|name| *name != id));
                Some(described(skill, entry))
            })
            .collect(),
    )
}

impl<T: HttpTransport> OpenCodeProvider<T> {
    /// The ids of the known skills [text] mentions, in order and once each.
    /// Only 2.x prompts name skills; a failed or slow listing sends none.
    pub(crate) async fn mentioned_skills(&mut self, text: &str) -> Vec<String> {
        let mentions = skill_mentions(text.trim());
        if self.config.generation != OpenCodeGeneration::V2 || mentions.is_empty() {
            return Vec::new();
        }
        let known: HashSet<String> =
            match tokio::time::timeout(INVENTORY_TIMEOUT, self.client.list_skills()).await {
                Ok(Ok(entries)) => entries
                    .iter()
                    .filter_map(|entry| entry.get("id").and_then(Value::as_str))
                    .map(str::to_owned)
                    .collect(),
                _ => HashSet::new(),
            };
        let mut named = Vec::new();
        for mention in mentions {
            if known.contains(&mention.name) && !named.contains(&mention.name) {
                named.push(mention.name);
            }
        }
        named
    }
}
