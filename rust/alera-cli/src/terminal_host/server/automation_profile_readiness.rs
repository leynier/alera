use alera_core::runtime::AgentProfile;
use std::path::{Path, PathBuf};

pub(super) async fn profile_executable_ready(profile: &AgentProfile) -> Result<(), String> {
    let (command, managed) = super::orchestration_profile_spawn::launch_for_profile(profile)?;
    let executable = managed
        .map(|launch| launch.executable)
        .or_else(|| command.and_then(|line| command_head(&line)))
        .ok_or_else(|| "The profile has no executable command".to_string())?;
    let path = crate::login_shell_environment::login_shell_variables_with_process_overrides()
        .await
        .get("PATH")
        .cloned()
        .unwrap_or_default();
    let name = executable.clone();
    let found = tokio::task::spawn_blocking(move || {
        let candidates: Vec<PathBuf> =
            if Path::new(&name).is_absolute() || name.contains('/') || name.contains('\\') {
                vec![PathBuf::from(&name)]
            } else {
                std::env::split_paths(&path)
                    .map(|base| base.join(&name))
                    .collect()
            };
        candidates.into_iter().any(|file| {
            if executable_file(&file) {
                return true;
            }
            cfg!(windows)
                && ["exe", "cmd", "bat", "com"]
                    .iter()
                    .any(|extension| executable_file(&file.with_extension(extension)))
        })
    })
    .await
    .unwrap_or(false);
    if found {
        Ok(())
    } else {
        Err(format!(
            "The profile command '{executable}' cannot be found on this runtime"
        ))
    }
}

fn command_head(line: &str) -> Option<String> {
    let mut quote = None;
    let mut token = String::new();
    for c in line.trim().chars() {
        match c {
            '\'' | '"' if quote == Some(c) => quote = None,
            '\'' | '"' if quote.is_none() => quote = Some(c),
            c if c.is_whitespace() && quote.is_none() => break,
            c => token.push(c),
        }
    }
    (!token.is_empty()).then_some(token)
}

fn executable_file(path: &Path) -> bool {
    let Ok(metadata) = path.metadata() else {
        return false;
    };
    if !metadata.is_file() {
        return false;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        metadata.permissions().mode() & 0o111 != 0
    }
    #[cfg(not(unix))]
    {
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn quoted_executable_keeps_spaces() {
        assert_eq!(
            command_head("\"/my agent/cli\" --model opus").as_deref(),
            Some("/my agent/cli")
        );
        assert_eq!(
            command_head("  codex --full-auto").as_deref(),
            Some("codex")
        );
        assert!(command_head(" ").is_none());
    }
}
