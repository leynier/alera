//! `alera tab link-agent`: binds a running agent to a tab again.
//!
//! Run from the agent's own shell tool, every identity comes from the
//! environment the agent passes to its commands. From any other shell, the
//! caller names the tab, the agent and its conversation or process.

use serde_json::{json, Value};

use crate::cli::{RuntimeDirArgs, TabLinkAgentArgs};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::protocol::RUNTIME_HOST_AGENT_PRESENCE_LINK_CAPABILITY;
use crate::{print_error, print_value, runtime_dir};

const USAGE_EXIT_CODE: i32 = 64;

/// The agent whose shell tool runs this command, as its environment shows it.
#[derive(Debug, Clone, PartialEq, Eq)]
struct DetectedAgent {
    agent_type: &'static str,
    session_id: Option<String>,
    pid: Option<u32>,
}

fn detect_agent(env: &impl Fn(&str) -> Option<String>) -> Option<DetectedAgent> {
    if env("CLAUDECODE").as_deref() == Some("1") {
        return Some(DetectedAgent {
            agent_type: "claude",
            session_id: env("CLAUDE_CODE_SESSION_ID"),
            pid: env("CLAUDE_PID").and_then(|pid| pid.parse().ok()),
        });
    }
    env("CODEX_THREAD_ID").map(|thread| DetectedAgent {
        agent_type: "codex",
        session_id: Some(thread),
        pid: None,
    })
}

pub(crate) fn link_request(
    args: &TabLinkAgentArgs,
    env: impl Fn(&str) -> Option<String>,
) -> Result<Value, String> {
    let env = |key: &str| env(key).filter(|value| !value.trim().is_empty());
    let detected = detect_agent(&env);
    let agent_type = args
        .agent
        .clone()
        .or_else(|| detected.as_ref().map(|agent| agent.agent_type.to_string()))
        .ok_or("--agent is required outside Claude Code and Codex")?;
    // Detected identity only describes the calling agent, never one named
    // explicitly with --agent.
    let detected = detected.filter(|agent| agent.agent_type == agent_type);
    let tab_id = args
        .tab
        .clone()
        .or_else(|| env("ALERA_TAB_ID"))
        .ok_or("--tab is required outside an Alera terminal")?;
    let session_id = args
        .session_id
        .clone()
        .or_else(|| detected.as_ref().and_then(|agent| agent.session_id.clone()));
    let pid = args
        .pid
        .or_else(|| detected.as_ref().and_then(|agent| agent.pid));
    let claude_config_dir = (agent_type == "claude" && detected.is_some())
        .then(|| env("CLAUDE_CONFIG_DIR"))
        .flatten();
    Ok(json!({
        "tabId": tab_id,
        "agentType": agent_type,
        "nativeSessionId": session_id,
        "agentPid": pid,
        "state": args.state,
        "sourceTerminalSessionId": args
            .source_terminal
            .clone()
            .or_else(|| env("ALERA_TERMINAL_SESSION_ID")),
        "claudeConfigDir": claude_config_dir,
    }))
}

pub(crate) async fn run(
    runtime: &RuntimeDirArgs,
    args: TabLinkAgentArgs,
    json_output: bool,
) -> i32 {
    let request = match link_request(&args, |key| std::env::var(key).ok()) {
        Ok(request) => request,
        Err(error) => {
            eprintln!("{error}");
            return USAGE_EXIT_CODE;
        }
    };
    let mut client = match RuntimeHostRpcClient::connect_or_start_with_required_capability(
        &runtime_dir(runtime),
        RUNTIME_HOST_AGENT_PRESENCE_LINK_CAPABILITY,
    )
    .await
    {
        Ok(client) => client,
        Err(error) => return print_error(error),
    };
    match client.request_value("agentPresence.link", &request).await {
        Ok(value) => {
            print_value(&value, json_output, &link_summary(&value));
            0
        }
        Err(error) => print_error(error),
    }
}

fn link_summary(value: &Value) -> String {
    let field = |key: &str| value.get(key).and_then(Value::as_str).unwrap_or("unknown");
    let mut summary = format!(
        "{} linked to tab {} (terminal {}), state {}",
        field("agentType"),
        field("tabId"),
        field("terminalSessionId"),
        field("state"),
    );
    if let Some(source) = value.get("reroutedFrom").and_then(Value::as_str) {
        summary.push_str(&format!(
            "\nHooks this agent sends from terminal {source} now update this tab."
        ));
    }
    summary
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use super::*;

    fn args() -> TabLinkAgentArgs {
        TabLinkAgentArgs {
            tab: None,
            agent: None,
            session_id: None,
            pid: None,
            source_terminal: None,
            state: "working".to_string(),
        }
    }

    fn env(pairs: &[(&str, &str)]) -> impl Fn(&str) -> Option<String> {
        let map: HashMap<String, String> = pairs
            .iter()
            .map(|(key, value)| (key.to_string(), value.to_string()))
            .collect();
        move |key| map.get(key).cloned()
    }

    #[test]
    fn inside_claude_everything_comes_from_the_environment() {
        let request = link_request(
            &args(),
            env(&[
                ("CLAUDECODE", "1"),
                ("CLAUDE_CODE_SESSION_ID", "conv-1"),
                ("CLAUDE_PID", "4242"),
                ("CLAUDE_CONFIG_DIR", "/home/me/.ccs/instances/work"),
                ("ALERA_TAB_ID", "tab-1"),
                ("ALERA_TERMINAL_SESSION_ID", "term-old"),
            ]),
        )
        .unwrap();

        assert_eq!(
            request,
            json!({
                "tabId": "tab-1",
                "agentType": "claude",
                "nativeSessionId": "conv-1",
                "agentPid": 4242,
                "state": "working",
                "sourceTerminalSessionId": "term-old",
                "claudeConfigDir": "/home/me/.ccs/instances/work",
            })
        );
    }

    #[test]
    fn inside_codex_the_thread_is_the_conversation() {
        let request = link_request(
            &TabLinkAgentArgs {
                tab: Some("tab-2".to_string()),
                ..args()
            },
            env(&[("CODEX_THREAD_ID", "thread-9"), ("ALERA_TAB_ID", "tab-1")]),
        )
        .unwrap();

        assert_eq!(request["agentType"], "codex");
        assert_eq!(request["nativeSessionId"], "thread-9");
        assert_eq!(request["tabId"], "tab-2");
        assert_eq!(request["agentPid"], Value::Null);
    }

    #[test]
    fn an_explicit_other_agent_ignores_the_callers_identity() {
        let request = link_request(
            &TabLinkAgentArgs {
                agent: Some("opencode".to_string()),
                session_id: Some("ses_1".to_string()),
                ..args()
            },
            env(&[
                ("CLAUDECODE", "1"),
                ("CLAUDE_CODE_SESSION_ID", "conv-1"),
                ("CLAUDE_PID", "4242"),
                ("CLAUDE_CONFIG_DIR", "/home/me/.claude"),
                ("ALERA_TAB_ID", "tab-1"),
            ]),
        )
        .unwrap();

        assert_eq!(request["agentType"], "opencode");
        assert_eq!(request["nativeSessionId"], "ses_1");
        assert_eq!(request["agentPid"], Value::Null);
        assert_eq!(request["claudeConfigDir"], Value::Null);
    }

    #[test]
    fn outside_an_agent_and_a_terminal_the_caller_must_name_them() {
        assert_eq!(
            link_request(&args(), env(&[("ALERA_TAB_ID", "tab-1")])),
            Err("--agent is required outside Claude Code and Codex".to_string())
        );
        assert_eq!(
            link_request(
                &TabLinkAgentArgs {
                    agent: Some("claude".to_string()),
                    ..args()
                },
                env(&[]),
            ),
            Err("--tab is required outside an Alera terminal".to_string())
        );
    }

    #[test]
    fn summary_mentions_the_rerouted_terminal() {
        let summary = link_summary(&json!({
            "agentType": "claude",
            "tabId": "tab-1",
            "terminalSessionId": "term-1",
            "state": "working",
            "reroutedFrom": "term-old",
        }));

        assert!(summary.starts_with("claude linked to tab tab-1 (terminal term-1), state working"));
        assert!(summary.contains("terminal term-old now update this tab"));
    }
}
