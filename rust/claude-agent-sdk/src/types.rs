use crate::error::{ClaudeSdkError, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;
use std::fmt;
use std::future::Future;
use std::path::PathBuf;
use std::pin::Pin;
use std::sync::Arc;
use std::time::Duration;

pub type JsonMap = BTreeMap<String, Value>;
pub type PermissionFuture = Pin<Box<dyn Future<Output = Result<PermissionResult>> + Send>>;
pub type HookFuture = Pin<Box<dyn Future<Output = Result<HookOutput>> + Send>>;
pub type McpFuture = Pin<Box<dyn Future<Output = Result<Option<Value>>> + Send>>;
pub type PermissionCallback =
    Arc<dyn Fn(String, Value, ToolPermissionContext) -> PermissionFuture + Send + Sync>;
pub type McpCallback = Arc<dyn Fn(String, Value) -> McpFuture + Send + Sync>;
pub type McpCallbackWithContext =
    Arc<dyn Fn(String, Value, ControlRequestContext) -> McpFuture + Send + Sync>;
pub type StderrCallback = Arc<dyn Fn(String) + Send + Sync>;

pub type PermissionMode = String;
pub type HookEvent = String;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ControlRequestContext {
    pub request_id: String,
    pub raw: Value,
}

impl ControlRequestContext {
    pub(crate) fn from_envelope(request_id: impl Into<String>, raw: &Value) -> Self {
        Self {
            request_id: request_id.into(),
            raw: raw.clone(),
        }
    }
}

impl Default for ControlRequestContext {
    fn default() -> Self {
        Self {
            request_id: String::new(),
            raw: Value::Null,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PermissionRuleValue {
    #[serde(rename = "toolName")]
    pub tool_name: String,
    #[serde(rename = "ruleContent", skip_serializing_if = "Option::is_none")]
    pub rule_content: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PermissionUpdate {
    #[serde(rename = "type")]
    pub kind: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rules: Option<Vec<PermissionRuleValue>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub behavior: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mode: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub directories: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub destination: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ToolPermissionContext {
    #[serde(default)]
    pub suggestions: Vec<PermissionUpdate>,
    #[serde(rename = "tool_use_id", skip_serializing_if = "Option::is_none")]
    pub tool_use_id: Option<String>,
    pub agent_id: Option<String>,
    pub blocked_path: Option<String>,
    pub decision_reason: Option<String>,
    /// The user-configured ask rule that made the CLI ask, when one did.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub matched_ask_rule: Option<Value>,
    /// The CLI asks hosts not to offer a standing "always allow" grant.
    #[serde(default, skip_serializing_if = "is_false")]
    pub suppress_always_allow_rule: bool,
    pub title: Option<String>,
    pub display_name: Option<String>,
    pub description: Option<String>,
    #[serde(default)]
    pub control: ControlRequestContext,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "behavior")]
pub enum PermissionResult {
    #[serde(rename = "allow")]
    Allow {
        #[serde(rename = "updatedInput", skip_serializing_if = "Option::is_none")]
        updated_input: Option<Value>,
        #[serde(rename = "updatedPermissions", skip_serializing_if = "Option::is_none")]
        updated_permissions: Option<Vec<PermissionUpdate>>,
    },
    #[serde(rename = "deny")]
    Deny {
        message: String,
        #[serde(default, skip_serializing_if = "is_false")]
        interrupt: bool,
    },
}

fn is_false(value: &bool) -> bool {
    !*value
}

impl PermissionResult {
    pub fn allow() -> Self {
        Self::Allow {
            updated_input: None,
            updated_permissions: None,
        }
    }

    pub fn deny(message: impl Into<String>) -> Self {
        Self::Deny {
            message: message.into(),
            interrupt: false,
        }
    }

    pub fn to_wire(&self, original_input: &Value) -> Value {
        match self {
            Self::Allow {
                updated_input,
                updated_permissions,
            } => {
                let mut result = serde_json::Map::new();
                result.insert("behavior".into(), Value::String("allow".into()));
                result.insert(
                    "updatedInput".into(),
                    updated_input
                        .clone()
                        .unwrap_or_else(|| original_input.clone()),
                );
                if let Some(permissions) = updated_permissions {
                    result.insert(
                        "updatedPermissions".into(),
                        serde_json::to_value(permissions).unwrap_or(Value::Array(Vec::new())),
                    );
                }
                Value::Object(result)
            }
            Self::Deny { message, interrupt } => {
                let mut result = serde_json::Map::new();
                result.insert("behavior".into(), Value::String("deny".into()));
                result.insert("message".into(), Value::String(message.clone()));
                if *interrupt {
                    result.insert("interrupt".into(), Value::Bool(true));
                }
                Value::Object(result)
            }
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct HookOutput {
    #[serde(rename = "continue", skip_serializing_if = "Option::is_none")]
    pub continue_: Option<bool>,
    #[serde(rename = "async", skip_serializing_if = "Option::is_none")]
    pub async_: Option<bool>,
    #[serde(flatten)]
    pub extra: JsonMap,
}

#[derive(Clone)]
pub struct HookMatcher {
    pub matcher: Option<String>,
    pub hooks: Vec<HookCallback>,
    pub timeout: Option<Duration>,
}

#[derive(Clone)]
pub struct HookCallback {
    pub callback: Arc<dyn Fn(Value, Option<String>, Value) -> HookFuture + Send + Sync>,
}

impl HookCallback {
    pub fn new<F, Fut>(callback: F) -> Self
    where
        F: Fn(Value, Option<String>, Value) -> Fut + Send + Sync + 'static,
        Fut: Future<Output = Result<HookOutput>> + Send + 'static,
    {
        Self {
            callback: Arc::new(move |input, tool_use_id, context| {
                Box::pin(callback(input, tool_use_id, context))
            }),
        }
    }
}

impl fmt::Debug for HookCallback {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("HookCallback(..)")
    }
}

impl fmt::Debug for HookMatcher {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("HookMatcher")
            .field("matcher", &self.matcher)
            .field("hooks", &self.hooks)
            .field("timeout", &self.timeout)
            .finish()
    }
}

pub type Hooks = BTreeMap<HookEvent, Vec<HookMatcher>>;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentDefinition {
    pub description: String,
    pub prompt: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tools: Option<Vec<String>>,
    #[serde(rename = "disallowedTools", skip_serializing_if = "Option::is_none")]
    pub disallowed_tools: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub skills: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub memory: Option<String>,
    #[serde(rename = "mcpServers", skip_serializing_if = "Option::is_none")]
    pub mcp_servers: Option<Vec<Value>>,
    #[serde(rename = "initialPrompt", skip_serializing_if = "Option::is_none")]
    pub initial_prompt: Option<String>,
    #[serde(rename = "maxTurns", skip_serializing_if = "Option::is_none")]
    pub max_turns: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub background: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub effort: Option<String>,
    #[serde(rename = "permissionMode", skip_serializing_if = "Option::is_none")]
    pub permission_mode: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ThinkingConfig {
    Adaptive,
    Disabled,
    Enabled {
        budget_tokens: u32,
        #[serde(skip_serializing_if = "Option::is_none")]
        display: Option<String>,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum Tools {
    Names(Vec<String>),
    Preset {
        #[serde(rename = "type")]
        kind: String,
        preset: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SystemPrompt {
    Text(String),
    Preset {
        preset: String,
        append: Option<String>,
        exclude_dynamic_sections: Option<bool>,
        snapshot: Option<bool>,
    },
    Custom {
        prompt: String,
        snapshot: Option<bool>,
    },
    File {
        path: String,
    },
}

#[derive(Clone)]
pub struct ClaudeAgentOptions {
    pub tools: Option<Tools>,
    pub allowed_tools: Vec<String>,
    pub system_prompt: Option<SystemPrompt>,
    pub mcp_servers: BTreeMap<String, Value>,
    pub strict_mcp_config: bool,
    pub permission_mode: Option<PermissionMode>,
    pub continue_conversation: bool,
    pub resume: Option<String>,
    pub session_id: Option<String>,
    pub max_turns: Option<u32>,
    pub max_budget_usd: Option<f64>,
    pub disallowed_tools: Vec<String>,
    pub model: Option<String>,
    pub fallback_model: Option<String>,
    pub betas: Vec<String>,
    pub permission_prompt_tool_name: Option<String>,
    pub cwd: Option<PathBuf>,
    pub cli_path: Option<PathBuf>,
    pub settings: Option<String>,
    pub add_dirs: Vec<PathBuf>,
    pub env: BTreeMap<String, String>,
    pub extra_args: BTreeMap<String, Option<String>>,
    pub max_buffer_size: usize,
    pub shutdown_timeout: Duration,
    pub initialize_timeout: Duration,
    pub run_end_timeout: Duration,
    pub include_partial_messages: bool,
    pub include_hook_events: bool,
    pub fork_session: bool,
    pub resume_session_at: Option<String>,
    pub resume_drops_turn: Option<String>,
    pub setting_sources: Option<Vec<String>>,
    pub skills: Option<Vec<String>>,
    pub forward_subagent_text: bool,
    pub verbatim_prompts: bool,
    pub enable_file_checkpointing: bool,
    pub max_thinking_tokens: Option<u32>,
    pub thinking: Option<ThinkingConfig>,
    pub effort: Option<String>,
    pub output_format: Option<Value>,
    pub task_budget: Option<u32>,
    pub agents: BTreeMap<String, AgentDefinition>,
    pub hooks: Hooks,
    pub permission_callback: Option<PermissionCallback>,
    pub mcp_callback: Option<McpCallback>,
    pub mcp_callback_with_context: Option<McpCallbackWithContext>,
    pub stderr_callback: Option<StderrCallback>,
}

impl Default for ClaudeAgentOptions {
    fn default() -> Self {
        Self {
            tools: None,
            allowed_tools: Vec::new(),
            system_prompt: None,
            mcp_servers: BTreeMap::new(),
            strict_mcp_config: false,
            permission_mode: None,
            continue_conversation: false,
            resume: None,
            session_id: None,
            max_turns: None,
            max_budget_usd: None,
            disallowed_tools: Vec::new(),
            model: None,
            fallback_model: None,
            betas: Vec::new(),
            permission_prompt_tool_name: None,
            cwd: None,
            cli_path: None,
            settings: None,
            add_dirs: Vec::new(),
            env: BTreeMap::new(),
            extra_args: BTreeMap::new(),
            max_buffer_size: 1024 * 1024,
            shutdown_timeout: Duration::from_secs(10),
            initialize_timeout: Duration::from_secs(60),
            run_end_timeout: Duration::from_secs(600),
            include_partial_messages: false,
            include_hook_events: false,
            fork_session: false,
            resume_session_at: None,
            resume_drops_turn: None,
            setting_sources: None,
            skills: None,
            forward_subagent_text: false,
            verbatim_prompts: false,
            enable_file_checkpointing: false,
            max_thinking_tokens: None,
            thinking: None,
            effort: None,
            output_format: None,
            task_budget: None,
            agents: BTreeMap::new(),
            hooks: BTreeMap::new(),
            permission_callback: None,
            mcp_callback: None,
            mcp_callback_with_context: None,
            stderr_callback: None,
        }
    }
}

impl fmt::Debug for ClaudeAgentOptions {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("ClaudeAgentOptions")
            .field("model", &self.model)
            .field("cwd", &self.cwd)
            .field("cli_path", &self.cli_path)
            .field("permission_mode", &self.permission_mode)
            .field("allowed_tools", &self.allowed_tools)
            .field("mcp_servers", &self.mcp_servers.keys().collect::<Vec<_>>())
            .field(
                "has_permission_callback",
                &self.permission_callback.is_some(),
            )
            .field(
                "has_mcp_callback",
                &(self.mcp_callback.is_some() || self.mcp_callback_with_context.is_some()),
            )
            .finish()
    }
}

impl ClaudeAgentOptions {
    pub fn validate(&self) -> Result<()> {
        if self.permission_callback.is_some() && self.permission_prompt_tool_name.is_some() {
            return Err(ClaudeSdkError::InvalidOptions(
                "permission_callback cannot be combined with permission_prompt_tool_name".into(),
            ));
        }
        if self.stderr_callback.is_some() {
            return Err(ClaudeSdkError::Unsupported("stderr_callback requires a stderr stream callback, which alera-agent-transport does not expose".into()));
        }
        if self.continue_conversation && (self.resume.is_some() || self.session_id.is_some()) {
            return Err(ClaudeSdkError::InvalidOptions(
                "continue_conversation cannot be combined with resume or session_id".into(),
            ));
        }
        if self.max_buffer_size == 0 {
            return Err(ClaudeSdkError::InvalidOptions(
                "max_buffer_size must be greater than zero".into(),
            ));
        }
        if let Some(skills) = &self.skills {
            for skill in skills {
                if skill.is_empty()
                    || skill
                        .chars()
                        .any(|character| matches!(character, ',' | '(' | ')' | '\n' | '\r'))
                {
                    return Err(ClaudeSdkError::InvalidOptions(format!(
                        "invalid skill name '{skill}'"
                    )));
                }
            }
        }
        if let Some(output_format) = &self.output_format {
            let is_json_schema =
                output_format.get("type").and_then(Value::as_str) == Some("json_schema");
            if !is_json_schema {
                return Err(ClaudeSdkError::Unsupported(
                    "only output_format type 'json_schema' is supported".into(),
                ));
            }
            if output_format.get("schema").is_none() {
                return Err(ClaudeSdkError::InvalidOptions(
                    "output_format json_schema requires a schema".into(),
                ));
            }
        }
        Ok(())
    }
}
