//! Grok skills from the CLI's own catalog, `grok inspect --json`, which honors
//! ignored and disabled skills and the nested plugin skills a flat folder scan
//! misses (T3 Code's `packages/provider-grok/src/server/skills.ts`).

use crate::GrokProviderConfig;
use alera_core::child_process::windowless_async_command;
use alera_core::login_shell_environment::apply_login_shell_environment;
use alera_provider_protocol::compare_skill_names;
use alera_provider_protocol::ProviderSkill;
use serde_json::Value;
use std::collections::BTreeMap;
use std::process::Stdio;
use std::time::Duration;
use tokio::io::AsyncReadExt;

const INSPECT_TIMEOUT: Duration = Duration::from_secs(4);
/// Far above any real catalog; a runaway writer cannot grow memory unbounded.
const MAX_INSPECT_OUTPUT_BYTES: u64 = 8 * 1024 * 1024;
/// Keeps probe runs from opening the updater console on Windows.
const DISABLE_AUTOUPDATER_ENV: &str = "GROK_DISABLE_AUTOUPDATER";

/// The skills `grok inspect --json` lists in `config.cwd`, sorted by name.
/// `Err` names the failing stage: spawn, timeout, exit or decode.
pub async fn discover_skills(config: &GrokProviderConfig) -> Result<Vec<ProviderSkill>, String> {
    let failure = |stage: &str, exit_code: Option<i32>| {
        let location = config
            .cwd
            .as_ref()
            .map(|cwd| format!(" for '{}'", cwd.display()))
            .unwrap_or_default();
        let exit_code = exit_code
            .map(|code| format!(" with exit code {code}"))
            .unwrap_or_default();
        format!("`grok inspect --json` failed during {stage}{location}{exit_code}.")
    };

    let executable = if config.executable.as_os_str().is_empty() {
        "grok".as_ref()
    } else {
        config.executable.as_os_str()
    };
    let mut command = windowless_async_command(executable);
    apply_login_shell_environment(&mut command, &BTreeMap::new()).await;
    command
        .args(["inspect", "--json"])
        .envs(config.effective_env())
        .env(DISABLE_AUTOUPDATER_ENV, "1")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .kill_on_drop(true);
    if let Some(cwd) = &config.cwd {
        command.current_dir(cwd);
    }
    let mut child = command.spawn().map_err(|_| failure("spawn", None))?;
    let Some(stdout) = child.stdout.take() else {
        let _ = child.kill().await;
        return Err(failure("spawn", None));
    };

    let collected = tokio::time::timeout(INSPECT_TIMEOUT, async {
        let mut output = Vec::new();
        let read = stdout
            .take(MAX_INSPECT_OUTPUT_BYTES + 1)
            .read_to_end(&mut output)
            .await;
        if read.is_err() || output.len() as u64 > MAX_INSPECT_OUTPUT_BYTES {
            return None;
        }
        Some((output, child.wait().await))
    })
    .await;
    let (output, status) = match collected {
        Err(_) => {
            let _ = child.kill().await;
            return Err(failure("timeout", None));
        }
        Ok(None) => {
            let _ = child.kill().await;
            return Err(failure("decode", None));
        }
        Ok(Some((output, status))) => (output, status),
    };
    let status = status.map_err(|_| failure("spawn", None))?;
    if !status.success() {
        return Err(failure("exit", status.code()));
    }
    decode_inspect_skills(&String::from_utf8_lossy(&output)).ok_or_else(|| failure("decode", None))
}

/// The skills in `grok inspect --json` output, or `None` when it is not a
/// JSON object with a `skills` array. Entries without a name or a source path
/// are skipped; a later entry with the same name replaces an earlier one.
pub fn decode_inspect_skills(stdout: &str) -> Option<Vec<ProviderSkill>> {
    let parsed: Value = serde_json::from_str(stdout).ok()?;
    let entries = parsed.as_object()?.get("skills")?.as_array()?;
    let mut skills: Vec<ProviderSkill> = Vec::new();
    for record in entries.iter().filter(|entry| entry.is_object()) {
        let text = |value: Option<&Value>| {
            value
                .and_then(Value::as_str)
                .map(str::trim)
                .unwrap_or_default()
                .to_owned()
        };
        let name = text(record.get("name"));
        let source = record.get("source").filter(|source| source.is_object());
        let path = text(source.and_then(|source| source.get("path")));
        let Some(skill) = ProviderSkill::from_native(&name, &path, true) else {
            continue;
        };
        let skill = ProviderSkill {
            enabled: record.get("userInvocable") != Some(&Value::Bool(false)),
            ..skill
        }
        .with_scope(Some(&text(source.and_then(|source| source.get("type")))))
        .with_description(Some(&text(record.get("description"))));
        match skills
            .iter_mut()
            .find(|existing| existing.name == skill.name)
        {
            Some(existing) => *existing = skill,
            None => skills.push(skill),
        }
    }
    skills.sort_by(|left, right| compare_skill_names(&left.name, &right.name));
    Some(skills)
}
