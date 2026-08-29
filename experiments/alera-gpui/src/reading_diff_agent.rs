use std::io::{Read, Write};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use alera_core::child_process::windowless_command;

pub(crate) struct ReadingDiffAgentRequest<'a> {
    pub agent: &'a str,
    pub model: &'a str,
    pub effort: Option<&'a str>,
    pub prompt: &'a str,
    pub working_directory: &'a str,
    pub timeout_seconds: u64,
    pub cancel: Arc<AtomicBool>,
}

struct AgentPlan {
    binary: String,
    arguments: Vec<String>,
    stdin: Option<String>,
    temporary_prompt: Option<PathBuf>,
    label: &'static str,
}

pub(crate) fn run_reading_diff_agent(request: ReadingDiffAgentRequest<'_>) -> Result<(String, String), String> {
    let plan = plan_agent(&request)?;
    let mut command = windowless_command(&plan.binary);
    command
        .args(&plan.arguments)
        .current_dir(request.working_directory)
        .stdin(if plan.stdin.is_some() {
            std::process::Stdio::piped()
        } else {
            std::process::Stdio::null()
        })
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped());
    let mut child = command.spawn().map_err(|_| {
        format!(
            "{} Could Not Start. Check That {} Is Installed And On PATH.",
            plan.label, plan.binary
        )
    })?;
    if let Some(stdin) = plan.stdin {
        child
            .stdin
            .take()
            .ok_or_else(|| "AI Text Process Stdin Is Unavailable.".to_string())?
            .write_all(stdin.as_bytes())
            .map_err(|error| error.to_string())?;
    }
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| "AI Text Process Stdout Is Unavailable.".to_string())?;
    let stderr = child
        .stderr
        .take()
        .ok_or_else(|| "AI Text Process Stderr Is Unavailable.".to_string())?;
    let stdout_thread = std::thread::spawn(move || {
        let mut bytes = Vec::new();
        let mut stream = stdout;
        let _ = stream.read_to_end(&mut bytes);
        bytes
    });
    let stderr_thread = std::thread::spawn(move || {
        let mut bytes = Vec::new();
        let mut stream = stderr;
        let _ = stream.read_to_end(&mut bytes);
        bytes
    });
    let started = Instant::now();
    let status = loop {
        if request.cancel.load(Ordering::Relaxed) {
            let _ = child.kill();
            let _ = child.wait();
            break Err("Reading Diff Generation Was Canceled.".to_string());
        }
        if started.elapsed() > Duration::from_secs(request.timeout_seconds.max(1)) {
            let _ = child.kill();
            let _ = child.wait();
            break Err(format!("{} Timed Out.", plan.label));
        }
        match child.try_wait() {
            Ok(Some(status)) => break Ok(status),
            Ok(None) => std::thread::sleep(Duration::from_millis(25)),
            Err(error) => break Err(error.to_string()),
        }
    };
    let stdout = stdout_thread.join().unwrap_or_default();
    let stderr = stderr_thread.join().unwrap_or_default();
    if let Some(path) = plan.temporary_prompt {
        let _ = std::fs::remove_file(path);
    }
    let status = status?;
    let stdout = String::from_utf8_lossy(&stdout).into_owned();
    let stderr = String::from_utf8_lossy(&stderr).into_owned();
    if !status.success() {
        return Err(if stderr.trim().is_empty() {
            format!("{} Exited With Code {}.", plan.label, status.code().unwrap_or(-1))
        } else {
            stderr.trim().to_string()
        });
    }
    let plan_json = extract_json_object(&stdout)
        .ok_or_else(|| format!("{} Returned No JSON Reading Plan.", plan.label))?;
    Ok((plan_json, plan.label.to_string()))
}

fn plan_agent(request: &ReadingDiffAgentRequest<'_>) -> Result<AgentPlan, String> {
    let model = request.model.trim();
    let effort = request.effort.filter(|value| !value.trim().is_empty());
    match request.agent {
        "codex" => {
            let mut arguments = vec![
                "exec", "--ephemeral", "--skip-git-repo-check", "--model", model,
                "--ignore-user-config", "--ignore-rules", "--strict-config",
                "-c", "default_permissions=\"alera_diff_only\"",
                "-c", "permissions.alera_diff_only={filesystem={\":minimal\"=\"read\",\":workspace_roots\"=\"read\"},network={enabled=false}}",
                "-c", "approval_policy=\"never\"",
                "-c", "shell_environment_policy.inherit=\"none\"",
                "-c", "web_search=\"disabled\"",
            ]
            .into_iter()
            .map(str::to_string)
            .collect::<Vec<_>>();
            if let Some(effort) = effort {
                arguments.extend(["-c".to_string(), format!("model_reasoning_effort={effort}")]);
            }
            for feature in DISABLED_CODEX_FEATURES {
                arguments.extend(["--disable".to_string(), (*feature).to_string()]);
            }
            Ok(AgentPlan {
                binary: "codex".into(),
                arguments,
                stdin: Some(request.prompt.to_string()),
                temporary_prompt: None,
                label: "Codex",
            })
        }
        "claude" => {
            let mut arguments = vec![
                "-p", "--output-format", "text", "--model", model,
                "--permission-mode", "plan", "--safe-mode", "--disable-slash-commands",
                "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}", "--tools", "", "--no-chrome",
            ]
            .into_iter()
            .map(str::to_string)
            .collect::<Vec<_>>();
            if let Some(effort) = effort {
                arguments.extend(["--effort".to_string(), effort.to_string()]);
            }
            Ok(AgentPlan {
                binary: "claude".into(),
                arguments,
                stdin: Some(request.prompt.to_string()),
                temporary_prompt: None,
                label: "Claude Code",
            })
        }
        "copilot" => {
            if request.prompt.len() > 24_000 {
                return Err("GitHub Copilot Cannot Receive This Diff Chunk Safely.".to_string());
            }
            let mut arguments = vec![
                "--prompt", request.prompt, "--silent", "--stream", "off",
                "--no-custom-instructions", "--model", model, "--available-tools=",
                "--excluded-tools=*", "--disable-builtin-mcps", "--no-ask-user", "--no-auto-update",
            ]
            .into_iter()
            .map(str::to_string)
            .collect::<Vec<_>>();
            if let Some(effort) = effort {
                arguments.extend(["--effort".to_string(), effort.to_string()]);
            }
            Ok(AgentPlan {
                binary: "copilot".into(),
                arguments,
                stdin: None,
                temporary_prompt: None,
                label: "GitHub Copilot",
            })
        }
        "pi" => {
            let mut arguments = vec![
                "--print", "--no-session", "--no-tools", "--no-extensions", "--no-skills",
                "--no-context-files", "--mode", "text", "--model", model,
            ]
            .into_iter()
            .map(str::to_string)
            .collect::<Vec<_>>();
            if let Some(effort) = effort {
                arguments.extend(["--thinking".to_string(), effort.to_string()]);
            }
            Ok(AgentPlan {
                binary: "pi".into(),
                arguments,
                stdin: Some(request.prompt.to_string()),
                temporary_prompt: None,
                label: "Pi",
            })
        }
        "grok" => {
            let path = std::env::temp_dir().join(format!(
                "alera-reading-diff-{}-{}.txt",
                std::process::id(),
                chrono::Utc::now().timestamp_nanos_opt().unwrap_or_default()
            ));
            std::fs::write(&path, request.prompt).map_err(|error| error.to_string())?;
            let mut arguments = vec![
                "--prompt-file".to_string(), path.to_string_lossy().into_owned(),
                "--output-format".into(), "plain".into(), "--model".into(), model.into(),
                "--tools".into(), "".into(), "--no-subagents".into(),
                "--disable-web-search".into(), "--no-memory".into(),
                "--max-turns".into(), "1".into(), "--verbatim".into(),
            ];
            if let Some(effort) = effort.filter(|value| *value != "default") {
                arguments.extend(["--effort".to_string(), effort.to_string()]);
            }
            Ok(AgentPlan {
                binary: "grok".into(),
                arguments,
                stdin: None,
                temporary_prompt: Some(path),
                label: "Grok Build",
            })
        }
        _ => Err("The Configured AI Text Agent Cannot Guarantee Diff-Only Access.".to_string()),
    }
}

fn extract_json_object(output: &str) -> Option<String> {
    let trimmed = output.trim();
    let start = trimmed.find('{')?;
    let end = trimmed.rfind('}')?;
    (end >= start).then(|| trimmed[start..=end].to_string())
}

const DISABLED_CODEX_FEATURES: &[&str] = &[
    "apps", "browser_use", "browser_use_external", "browser_use_full_cdp_access",
    "computer_use", "hooks", "image_generation", "in_app_browser", "memories",
    "multi_agent", "plugins", "remote_plugin", "skill_search", "tool_suggest", "view_image",
];

#[cfg(test)]
mod tests {
    use std::sync::atomic::AtomicBool;
    use std::sync::Arc;

    use super::{extract_json_object, plan_agent, ReadingDiffAgentRequest};

    #[test]
    fn extracts_plan_from_cli_preamble_and_fence() {
        assert_eq!(
            extract_json_object("thinking\n```json\n{\"summary\":\"ok\"}\n```").as_deref(),
            Some("{\"summary\":\"ok\"}")
        );
    }

    #[test]
    fn codex_reading_diff_plan_disables_tools_network_and_user_config() {
        let request = ReadingDiffAgentRequest {
            agent: "codex",
            model: "gpt-5.5",
            effort: Some("low"),
            prompt: "diff",
            working_directory: ".",
            timeout_seconds: 30,
            cancel: Arc::new(AtomicBool::new(false)),
        };
        let plan = plan_agent(&request).expect("codex plan");
        assert!(plan.arguments.contains(&"--ignore-user-config".to_string()));
        assert!(plan.arguments.contains(&"--strict-config".to_string()));
        assert!(plan.arguments.contains(&"computer_use".to_string()));
        assert!(plan
            .arguments
            .contains(&"web_search=\"disabled\"".to_string()));
    }
}
