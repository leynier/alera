//! Rust provider SDK for the Claude Code stream-json protocol.
//!
//! The crate mirrors the provider-facing part of Anthropic's Python SDK while
//! using Alera's injectable [`alera_agent_transport::JsonTransport`] boundary.
//! `ClaudeClient` owns a reader task, routes control responses by request id,
//! answers permission, hook, and MCP callbacks, and bounds every control and
//! shutdown operation with a timeout. No Python runtime is required.
//!
//! The port intentionally excludes Python-only session storage and transcript mirroring adapters, Python MCP server objects, plugin helpers, and AnyIO runtime integration. `ClaudeAgentOptions::validate` rejects the currently unrepresentable stderr callback and non-`json_schema` output format, while the other excluded surfaces have no Rust API and therefore cannot be silently selected.

mod client;
mod control;
mod error;
mod message;
mod process;
mod query;
mod types;

pub use client::ClaudeClient;
pub use error::{ClaudeSdkError, Result};
pub use message::{
    AssistantMessage, ContentBlock, ConversationResetMessage, DeferredToolUse, Message,
    RateLimitEvent, RateLimitInfo, ResultMessage, ServerToolResultBlock, ServerToolUseBlock,
    StreamEvent, SystemMessage, TextBlock, ThinkingBlock, ToolResultBlock, ToolUseBlock,
    UserMessage, UserPrompt,
};
pub use query::{query, query_messages, Query};
pub use types::{
    AgentDefinition, ClaudeAgentOptions, ControlRequestContext, HookCallback, HookMatcher,
    HookOutput, McpCallback, McpCallbackWithContext, PermissionCallback, PermissionResult,
    PermissionRuleValue, PermissionUpdate, SystemPrompt, ThinkingConfig, ToolPermissionContext,
    Tools,
};

pub use alera_agent_transport::{JsonTransport, ProcessConfig, TransportError};
