//! Native provider session/thread resume for supported agent CLIs.
//!
//! Hooks supply a conversation, session, or thread identifier. The host stores
//! that id on the tab and, when a later PTY would otherwise start a new chat,
//! splices the adapter's resume shape into the launch. Missing or unusable ids
//! leave the existing launch unchanged.

use serde_json::Value;

use super::managed_agent_launch::ManagedAgentLaunch;

pub const AGENT_NATIVE_SESSION_ID_KEY: &str = "agentNativeSessionId";
pub const AGENT_NATIVE_SESSION_AGENT_KEY: &str = "agentNativeSessionAgent";

const NATIVE_ID_KEYS: [&str; 7] = [
    "conversation_id",
    "conversationId",
    "session_id",
    "sessionId",
    "sessionID",
    "thread_id",
    "threadId",
];

const PARENT_ID_KEYS: [&str; 3] = ["parent_session_id", "parentSessionId", "parentThreadId"];

/// How a supported agent CLI accepts a stored native session or thread id.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AgentSessionResumeShape {
    /// Tokens before the id, e.g. `resume` or `threads continue`.
    Subcommand(&'static [&'static str]),
    /// A separate flag and id, e.g. `--resume <id>`.
    Flag(&'static str),
    /// A single `--flag=<id>` token, required when the flag's value is optional.
    EqualsFlag(&'static str),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct ShellFamily {
    kind: ShellKind,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ShellKind {
    Posix,
    PowerShell,
    Cmd,
}

/// The provider session/thread id a hook payload carries, if any.
pub fn native_session_id(payload: &Value) -> Option<&str> {
    NATIVE_ID_KEYS.iter().find_map(|key| {
        payload
            .get(*key)
            .and_then(Value::as_str)
            .and_then(usable_native_session_id)
    })
}

pub fn hook_identifies_parent_session(payload: &Value) -> bool {
    PARENT_ID_KEYS.iter().any(|key| {
        payload
            .get(*key)
            .and_then(Value::as_str)
            .is_some_and(|id| !id.is_empty())
    })
}

pub fn usable_native_session_id(id: &str) -> Option<&str> {
    let id = id.trim();
    if id.is_empty() {
        return None;
    }
    if id.chars().any(|ch| {
        ch.is_whitespace()
            || ch.is_control()
            || matches!(ch, '|' | '&' | ';' | '<' | '>' | '$' | '`' | '(' | ')')
    }) {
        return None;
    }
    Some(id)
}

pub fn resume_arguments(shape: AgentSessionResumeShape, session_id: &str) -> Option<Vec<String>> {
    let session_id = usable_native_session_id(session_id)?;
    Some(match shape {
        AgentSessionResumeShape::Subcommand(tokens) => tokens
            .iter()
            .copied()
            .map(str::to_string)
            .chain(std::iter::once(session_id.to_string()))
            .collect(),
        AgentSessionResumeShape::Flag(flag) => vec![flag.to_string(), session_id.to_string()],
        AgentSessionResumeShape::EqualsFlag(flag) => {
            vec![format!("{flag}={session_id}")]
        }
    })
}

pub fn apply_resume_to_managed_launch(
    launch: &mut ManagedAgentLaunch,
    shape: AgentSessionResumeShape,
    session_id: &str,
) -> bool {
    let Some(arguments) = resume_arguments(shape, session_id) else {
        return false;
    };
    let mut next = arguments;
    next.append(&mut launch.arguments);
    launch.arguments = next;
    true
}

/// Appends or splices resume tokens onto an opaque Command-mode line.
///
/// Flag shapes append, so the host never has to split the user's line. Codex
/// and Amp take a subcommand, which has to sit after the executable; that
/// splice is skipped when the line already uses shell operators.
pub fn apply_resume_to_command(
    command: &str,
    shape: AgentSessionResumeShape,
    session_id: &str,
    shell: &str,
) -> Option<String> {
    let arguments = resume_arguments(shape, session_id)?;
    let family = shell_family(shell);
    let quoted = arguments
        .iter()
        .map(|token| quote_argument(token, family))
        .collect::<Vec<_>>()
        .join(" ");
    match shape {
        AgentSessionResumeShape::Flag(_) | AgentSessionResumeShape::EqualsFlag(_) => {
            let command = command.trim();
            if command.is_empty() {
                return None;
            }
            Some(format!("{command} {quoted}"))
        }
        AgentSessionResumeShape::Subcommand(_) => splice_after_executable(command, &quoted),
    }
}

fn splice_after_executable(command: &str, quoted_resume: &str) -> Option<String> {
    let command = command.trim();
    if command.is_empty() || has_shell_operator(command) {
        return None;
    }
    let executable_end = command.find(char::is_whitespace).unwrap_or(command.len());
    let executable = &command[..executable_end];
    let rest = command[executable_end..].trim_start();
    if rest.is_empty() {
        Some(format!("{executable} {quoted_resume}"))
    } else {
        Some(format!("{executable} {quoted_resume} {rest}"))
    }
}

fn has_shell_operator(command: &str) -> bool {
    command.contains("&&")
        || command.contains("||")
        || command.contains('|')
        || command.contains(';')
}

fn shell_family(shell: &str) -> ShellFamily {
    let normalized = shell.replace('\\', "/").to_ascii_lowercase();
    let executable = normalized.rsplit('/').next().unwrap_or(&normalized);
    let kind = if matches!(
        executable,
        "powershell" | "powershell.exe" | "pwsh" | "pwsh.exe"
    ) {
        ShellKind::PowerShell
    } else if matches!(executable, "cmd" | "cmd.exe") {
        ShellKind::Cmd
    } else {
        ShellKind::Posix
    };
    ShellFamily { kind }
}

fn quote_argument(value: &str, family: ShellFamily) -> String {
    match family.kind {
        ShellKind::Posix => format!("'{}'", value.replace('\'', "'\"'\"'")),
        ShellKind::PowerShell => format!("'{}'", value.replace('\'', "''")),
        ShellKind::Cmd => format!("\"{}\"", value.replace('"', "\"\"")),
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn store_path_reads_native_ids_and_ignores_parent_or_empty_payloads() {
        assert_eq!(
            native_session_id(&json!({"session_id": "sess-1"})),
            Some("sess-1")
        );
        assert_eq!(
            native_session_id(&json!({"threadId": " thread-2 "})),
            Some("thread-2")
        );
        assert_eq!(
            native_session_id(&json!({"conversationId": "conv-3"})),
            Some("conv-3")
        );
        assert_eq!(native_session_id(&json!({"prompt": "hello"})), None);
        assert_eq!(native_session_id(&json!({"session_id": "  "})), None);
        assert_eq!(native_session_id(&json!({"session_id": "bad;id"})), None);
        assert!(hook_identifies_parent_session(&json!({
            "session_id": "child",
            "parent_session_id": "parent"
        })));
        assert!(!hook_identifies_parent_session(
            &json!({"session_id": "child"})
        ));
    }

    #[test]
    fn resume_path_builds_per_agent_tokens() {
        assert_eq!(
            resume_arguments(AgentSessionResumeShape::Subcommand(&["resume"]), "abc-1").unwrap(),
            ["resume", "abc-1"]
        );
        assert_eq!(
            resume_arguments(
                AgentSessionResumeShape::Subcommand(&["threads", "continue"]),
                "thread-1"
            )
            .unwrap(),
            ["threads", "continue", "thread-1"]
        );
        assert_eq!(
            resume_arguments(AgentSessionResumeShape::Flag("--resume"), "sess-1").unwrap(),
            ["--resume", "sess-1"]
        );
        assert_eq!(
            resume_arguments(AgentSessionResumeShape::EqualsFlag("--resume"), "sess-1").unwrap(),
            ["--resume=sess-1"]
        );
    }

    #[test]
    fn resume_path_splices_managed_argv_and_command_lines() {
        let mut launch = ManagedAgentLaunch {
            executable: "codex".into(),
            arguments: vec!["--search".into()],
        };
        assert!(apply_resume_to_managed_launch(
            &mut launch,
            AgentSessionResumeShape::Subcommand(&["resume"]),
            "sess-1"
        ));
        assert_eq!(launch.arguments, ["resume", "sess-1", "--search"]);

        assert_eq!(
            apply_resume_to_command(
                "claude --permission-mode auto",
                AgentSessionResumeShape::Flag("--resume"),
                "sess-1",
                "/bin/zsh"
            )
            .as_deref(),
            Some("claude --permission-mode auto '--resume' 'sess-1'")
        );
        assert_eq!(
            apply_resume_to_command(
                "codex --search",
                AgentSessionResumeShape::Subcommand(&["resume"]),
                "sess-1",
                "/bin/zsh"
            )
            .as_deref(),
            Some("codex 'resume' 'sess-1' --search")
        );
        assert_eq!(
            apply_resume_to_command(
                "copilot --allow-all",
                AgentSessionResumeShape::EqualsFlag("--resume"),
                "sess-1",
                "/bin/zsh"
            )
            .as_deref(),
            Some("copilot --allow-all '--resume=sess-1'")
        );
    }

    #[test]
    fn missing_id_path_does_not_change_the_launch() {
        let original = ManagedAgentLaunch {
            executable: "codex".into(),
            arguments: vec!["--search".into()],
        };
        let mut launch = original.clone();
        assert!(!apply_resume_to_managed_launch(
            &mut launch,
            AgentSessionResumeShape::Subcommand(&["resume"]),
            "   "
        ));
        assert_eq!(launch, original);
        assert!(apply_resume_to_command(
            "codex --search",
            AgentSessionResumeShape::Subcommand(&["resume"]),
            "",
            "/bin/zsh"
        )
        .is_none());
        assert!(apply_resume_to_command(
            "codex --search && printf done",
            AgentSessionResumeShape::Subcommand(&["resume"]),
            "sess-1",
            "/bin/zsh"
        )
        .is_none());
        assert!(resume_arguments(AgentSessionResumeShape::Flag("--resume"), "a|b").is_none());
    }
}
