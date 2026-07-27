use std::env;

use alera_core::child_process::windowless_async_command;
use tokio::process::Command;
use tokio::sync::OnceCell;
use tokio::time::{timeout, Duration};

const SHELL_PATH_HYDRATION_DELIMITER: &str = "__ALERA_SHELL_PATH__";
const SHELL_PATH_HYDRATION_TIMEOUT: Duration = Duration::from_secs(10);

/// Only a successful hydration is cached, so a transient failure (a slow profile
/// that overruns the timeout, a shell that fails to launch) is retried on the
/// next call instead of poisoning the process for its whole lifetime.
static LOGIN_SHELL_PATH: OnceCell<Vec<String>> = OnceCell::const_new();

/// PATH entries as seen by the user's login shell, resolved once per process.
///
/// GUI launches (macOS `launchd`, desktop `.desktop` entries) start the app with
/// a minimal PATH that omits Homebrew and other user-installed prefixes, so any
/// tool the host spawns by bare name would otherwise be unresolvable.
pub(crate) async fn login_shell_path_segments() -> Option<&'static Vec<String>> {
    if cfg!(windows) {
        return None;
    }
    LOGIN_SHELL_PATH
        .get_or_try_init(|| async {
            let shell = pick_user_shell().ok_or(())?;
            hydrate_shell_path(&shell).await.ok_or(())
        })
        .await
        .ok()
}

/// Login-shell PATH merged ahead of `existing`, or `None` when nothing changes.
pub(crate) async fn login_shell_merged_path(existing: Option<&str>) -> Option<String> {
    let segments = login_shell_path_segments().await?;
    merged_path_value(existing, segments)
}

/// Give `command` the login-shell PATH so tools installed under a user prefix
/// (Homebrew, `~/.local/bin`, version managers) resolve by bare name.
pub(crate) async fn apply_login_shell_path(command: &mut Command) {
    let inherited = env::var("PATH").ok();
    if let Some(path) = login_shell_merged_path(inherited.as_deref()).await {
        command.env("PATH", path);
    }
}

pub(crate) async fn setup_command_environment() -> Vec<(String, String)> {
    let mut environment = env::vars().collect::<Vec<_>>();
    if cfg!(windows) {
        return environment;
    }
    if let Some(segments) = login_shell_path_segments().await {
        merge_path_segments(&mut environment, segments);
    }
    environment
}

pub(crate) fn pick_user_shell() -> Option<String> {
    let shell = env::var("SHELL").ok().map(|value| value.trim().to_string());
    if let Some(shell) = shell.filter(|value| !value.is_empty()) {
        return Some(shell);
    }
    if cfg!(target_os = "macos") {
        Some("/bin/zsh".to_string())
    } else {
        Some("/bin/bash".to_string())
    }
}

async fn hydrate_shell_path(shell: &str) -> Option<Vec<String>> {
    let command = format!(
        "printf '%s' '{delimiter}'; printf '%s' \"$PATH\"; printf '%s' '{delimiter}'",
        delimiter = SHELL_PATH_HYDRATION_DELIMITER,
    );
    let mut process = windowless_async_command(shell);
    process.args(["-ilc", &command]);
    let output = match timeout(SHELL_PATH_HYDRATION_TIMEOUT, process.output()).await {
        Ok(Ok(output)) => output,
        Ok(Err(_)) | Err(_) => return None,
    };
    let segments = parse_hydrated_shell_path(&output.stdout);
    if segments.is_empty() {
        None
    } else {
        Some(segments)
    }
}

fn parse_hydrated_shell_path(stdout: &[u8]) -> Vec<String> {
    let cleaned = String::from_utf8_lossy(stdout);
    let Some(first) = cleaned.find(SHELL_PATH_HYDRATION_DELIMITER) else {
        return Vec::new();
    };
    let start = first + SHELL_PATH_HYDRATION_DELIMITER.len();
    let Some(second) = cleaned[start..].find(SHELL_PATH_HYDRATION_DELIMITER) else {
        return Vec::new();
    };
    split_path_segments(&cleaned[start..start + second])
}

pub(crate) fn merge_path_segments(
    environment: &mut Vec<(String, String)>,
    shell_segments: &[String],
) {
    let existing = environment
        .iter()
        .position(|(key, _)| key == "PATH")
        .and_then(|index| {
            environment
                .get(index)
                .map(|(_, value)| (index, value.clone()))
        });
    let merged = merged_path_value(
        existing.as_ref().map(|(_, value)| value.as_str()),
        shell_segments,
    );
    let Some(value) = merged else {
        return;
    };
    if let Some((index, _)) = existing {
        environment[index].1 = value;
    } else {
        environment.push(("PATH".to_string(), value));
    }
}

fn merged_path_value(existing: Option<&str>, shell_segments: &[String]) -> Option<String> {
    let existing_segments = existing.map(split_path_segments).unwrap_or_default();
    let mut merged = Vec::<String>::new();
    for segment in shell_segments.iter().chain(existing_segments.iter()) {
        if !segment.is_empty() && !merged.iter().any(|value| value == segment) {
            merged.push(segment.clone());
        }
    }
    if merged.is_empty() {
        return None;
    }
    Some(merged.join(":"))
}

fn split_path_segments(value: &str) -> Vec<String> {
    value
        .split(':')
        .filter(|segment| !segment.is_empty())
        .map(ToString::to_string)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::{merge_path_segments, merged_path_value, parse_hydrated_shell_path};

    #[test]
    fn parse_hydrated_shell_path_extracts_marked_segments() {
        let stdout = b"noise__ALERA_SHELL_PATH__/shell/bin:/usr/bin__ALERA_SHELL_PATH__";

        assert_eq!(
            parse_hydrated_shell_path(stdout),
            vec!["/shell/bin".to_string(), "/usr/bin".to_string()]
        );
    }

    #[test]
    fn merge_path_segments_prepends_shell_path_without_duplicates() {
        let mut environment = vec![("PATH".to_string(), "/usr/bin:/bin".to_string())];

        merge_path_segments(
            &mut environment,
            &["/custom/bin".to_string(), "/usr/bin".to_string()],
        );

        assert_eq!(environment[0].1, "/custom/bin:/usr/bin:/bin");
    }

    #[test]
    fn merge_path_segments_adds_path_when_missing() {
        let mut environment = vec![("HOME".to_string(), "/home/user".to_string())];

        merge_path_segments(&mut environment, &["/custom/bin".to_string()]);

        assert_eq!(
            environment[1],
            ("PATH".to_string(), "/custom/bin".to_string())
        );
    }

    #[test]
    fn merged_path_value_puts_login_segments_ahead_of_the_inherited_path() {
        let merged = merged_path_value(
            Some("/usr/bin:/bin:/usr/sbin:/sbin"),
            &[
                "/opt/homebrew/bin".to_string(),
                "/usr/local/bin".to_string(),
                "/usr/bin".to_string(),
            ],
        );

        assert_eq!(
            merged.unwrap(),
            "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        );
    }

    #[test]
    fn merged_path_value_is_none_without_any_segments() {
        assert_eq!(merged_path_value(None, &[]), None);
    }
}
