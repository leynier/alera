use std::process::Stdio;
use std::time::Duration;

use alera_core::child_process::windowless_async_command;
use regex::Regex;
use serde_json::{json, Value};

use crate::terminal_host::host_error::{HostError, HostResult};

use super::host_service_requests::required_non_blank;
use super::{ServerActor, ServerCommand};

const DISCOVERY_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_DISCOVERY_OUTPUT_BYTES: usize = 1024 * 1024;

impl ServerActor {
    pub(super) fn start_agent_profile_persona_discovery(
        &mut self,
        client_id: u64,
        request_id: i64,
        payload: &Value,
    ) -> HostResult<()> {
        let adapter = required_non_blank(payload, "adapter")?.to_ascii_lowercase();
        let (binary, arguments) = match adapter.as_str() {
            "agy" => ("agy", &["agents"][..]),
            "opencode" => ("opencode", &["agent", "list"][..]),
            _ => {
                return Err(HostError::format(format!(
                    "{adapter} does not support persona discovery."
                )))
            }
        };
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let result = Ok(discover_personas(&adapter, binary, arguments).await);
            let _ = inbox.send(ServerCommand::HostToolFinished {
                client_id,
                request_id,
                result,
                operation_id: None,
                skill: None,
            });
        });
        Ok(())
    }
}

async fn discover_personas(adapter: &str, binary: &str, arguments: &[&str]) -> Value {
    let mut command = windowless_async_command(binary);
    command
        .args(arguments)
        .kill_on_drop(true)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    crate::login_shell_environment::apply_login_shell_path(&mut command).await;
    let child = match command.spawn() {
        Ok(child) => child,
        Err(_) => {
            return failure(
                adapter,
                format!("{binary} Persona Discovery Could Not Be Started."),
            )
        }
    };
    let output = match tokio::time::timeout(DISCOVERY_TIMEOUT, child.wait_with_output()).await {
        Ok(Ok(output)) => output,
        Ok(Err(error)) => return failure(adapter, error.to_string()),
        Err(_) => return failure(adapter, "Persona Discovery Timed Out.".to_owned()),
    };
    if output.stdout.len() + output.stderr.len() > MAX_DISCOVERY_OUTPUT_BYTES {
        return failure(
            adapter,
            "Persona Discovery Returned Too Much Data.".to_owned(),
        );
    }
    if !output.status.success() {
        return failure(adapter, format!("Persona Discovery Failed For {adapter}."));
    }
    let stdout = String::from_utf8_lossy(&output.stdout);
    let personas = match adapter {
        "agy" => parse_agy_personas(&stdout),
        "opencode" => parse_opencode_personas(&stdout),
        _ => Vec::new(),
    };
    json!({
        "success": true,
        "adapter": adapter,
        "personas": personas,
    })
}

fn failure(adapter: &str, error: String) -> Value {
    json!({
        "success": false,
        "adapter": adapter,
        "personas": [],
        "error": error,
    })
}

fn parse_agy_personas(output: &str) -> Vec<String> {
    let valid = Regex::new(r"^[A-Za-z0-9_.-]+$").expect("valid persona regex");
    unique(
        output
            .lines()
            .map(|line| line.trim().trim_start_matches(['-', '*']).trim().to_owned())
            .filter(|line| {
                !line.is_empty()
                    && !line.eq_ignore_ascii_case("available agents:")
                    && valid.is_match(line)
            }),
    )
}

fn parse_opencode_personas(output: &str) -> Vec<String> {
    let pattern = Regex::new(r"^\s*([A-Za-z0-9_.-]+)\s+\((?:primary|subagent|all)\)")
        .expect("valid OpenCode persona regex");
    unique(output.lines().filter_map(|line| {
        pattern
            .captures(line)
            .and_then(|captures| captures.get(1))
            .map(|name| name.as_str().to_owned())
    }))
}

fn unique(values: impl IntoIterator<Item = String>) -> Vec<String> {
    let mut seen = std::collections::HashSet::new();
    values
        .into_iter()
        .filter(|value| seen.insert(value.clone()))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::{parse_agy_personas, parse_opencode_personas};

    #[test]
    fn parses_agy_persona_list() {
        assert_eq!(
            parse_agy_personas("Available agents:\n- build\n* review\nbuild\nnot valid\n"),
            ["build", "review"]
        );
    }

    #[test]
    fn parses_opencode_persona_list() {
        assert_eq!(
            parse_opencode_personas(
                "build (primary)\nreview (subagent)\nhidden (disabled)\nreview (all)\n"
            ),
            ["build", "review"]
        );
    }
}
