use serde_json::{Map, Value};

#[derive(Clone, Debug, PartialEq)]
pub(super) struct AgentProfileRecord {
    pub(super) id: String,
    pub(super) name: String,
    pub(super) sort_order: i64,
    pub(super) agent_type: String,
    pub(super) command: String,
    pub(super) launch_mode: String,
    pub(super) managed_config: Map<String, Value>,
    pub(super) custom_prompt: String,
    pub(super) description: String,
    pub(super) quota_group: Option<String>,
    pub(super) revision: i64,
}

pub(super) fn parse_agent_profiles(payload: Value) -> Result<Vec<AgentProfileRecord>, String> {
    let items = payload
        .get("items")
        .and_then(Value::as_array)
        .or_else(|| payload.as_array())
        .ok_or_else(|| "Agent Profile List Omitted Items".to_owned())?;
    items.iter().map(parse_agent_profile).collect()
}

pub(super) fn parse_agent_profile(value: &Value) -> Result<AgentProfileRecord, String> {
    let string = |key: &str| {
        value
            .get(key)
            .and_then(Value::as_str)
            .map(str::to_owned)
            .ok_or_else(|| format!("Agent Profile Omitted {}", title_from_key(key)))
    };
    Ok(AgentProfileRecord {
        id: string("id")?,
        name: string("name")?,
        sort_order: value
            .get("sortOrder")
            .and_then(Value::as_i64)
            .unwrap_or(0),
        agent_type: string("agentType")?,
        command: string("command")?,
        launch_mode: value
            .get("launchMode")
            .and_then(Value::as_str)
            .unwrap_or("command")
            .to_owned(),
        managed_config: value
            .get("managedConfig")
            .and_then(Value::as_object)
            .cloned()
            .unwrap_or_default(),
        custom_prompt: value
            .get("customPrompt")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned(),
        description: value
            .get("description")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned(),
        quota_group: value
            .get("quotaGroup")
            .and_then(Value::as_str)
            .map(str::to_owned),
        revision: value
            .get("revision")
            .and_then(Value::as_i64)
            .filter(|revision| *revision >= 0)
            .unwrap_or(0),
    })
}

fn title_from_key(key: &str) -> String {
    let mut title = String::new();
    for character in key.chars() {
        if character.is_ascii_uppercase() {
            title.push(' ');
        }
        if title.is_empty() {
            title.push(character.to_ascii_uppercase());
        } else {
            title.push(character);
        }
    }
    title
}
