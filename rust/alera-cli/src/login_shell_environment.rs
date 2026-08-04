use std::collections::BTreeMap;
use std::env;

use alera_core::child_process::windowless_async_command;
use tokio::process::Command;
use tokio::sync::RwLock;
use tokio::time::{timeout, Duration};

const SHELL_PATH_HYDRATION_DELIMITER: &str = "__ALERA_SHELL_PATH__";
const SHELL_ENVIRONMENT_HYDRATION_DELIMITER: &str = "__ALERA_SHELL_ENV__";
const SHELL_PATH_HYDRATION_TIMEOUT: Duration = Duration::from_secs(10);

/// Resolved login-shell PATH, held behind a lock so a mid-session reload can
/// replace it. Only a successful hydration is ever stored, so a transient
/// failure (a slow profile that overruns the timeout, a shell that fails to
/// launch) is retried on the next call and never poisons a previously good
/// value.
static LOGIN_SHELL_PATH: RwLock<Option<Vec<String>>> = RwLock::const_new(None);

/// Everything the user's login shell exports, resolved once and cached under
/// the same retry rules as [`LOGIN_SHELL_PATH`].
///
/// A GUI launch inherits none of the user's rc-file exports, so a host-side
/// lookup of something like `CCS_DIR` or `ANTHROPIC_API_KEY` would disagree
/// with what the same tool sees inside a terminal tab, where the shell sources
/// those files itself. Values may be secrets: this map is held in memory only
/// and must never be logged or persisted.
static LOGIN_SHELL_VARIABLES: RwLock<Option<BTreeMap<String, String>>> = RwLock::const_new(None);

/// PATH entries as seen by the user's login shell, resolved once and cached.
///
/// GUI launches (macOS `launchd`, desktop `.desktop` entries) start the app with
/// a minimal PATH that omits Homebrew and other user-installed prefixes, so any
/// tool the host spawns by bare name would otherwise be unresolvable.
pub(crate) async fn login_shell_path_segments() -> Option<Vec<String>> {
    resolve_login_shell_path(false).await
}

/// Variables as seen by the user's login shell, resolved once and cached.
pub(crate) async fn login_shell_variables() -> Option<BTreeMap<String, String>> {
    resolve_login_shell_variables(false).await
}

/// Re-probe the user's login shell, replacing both caches, and report how many
/// PATH entries and variables the refresh produced. Lets a tool installed or a
/// variable exported mid-session take effect without restarting the host.
///
/// Best-effort: a failed probe leaves the previous values in place and reports
/// their sizes. Both caches refresh together because PATH is read out of the
/// same probe, so refreshing one alone would re-derive it from the other's
/// stale values.
pub(crate) async fn reload_login_shell_environment() -> (usize, usize) {
    let variables = match resolve_login_shell_variables(true).await {
        Some(variables) => variables.len(),
        None => LOGIN_SHELL_VARIABLES
            .read()
            .await
            .as_ref()
            .map_or(0, BTreeMap::len),
    };
    let path = match resolve_login_shell_path(true).await {
        Some(segments) => segments.len(),
        None => LOGIN_SHELL_PATH.read().await.as_ref().map_or(0, Vec::len),
    };
    (path, variables)
}

async fn resolve_login_shell_path(force: bool) -> Option<Vec<String>> {
    if cfg!(windows) {
        return None;
    }
    if !force {
        if let Some(cached) = LOGIN_SHELL_PATH.read().await.as_ref() {
            return Some(cached.clone());
        }
    }
    // Hydration is intentionally not done under the write lock: it can take
    // seconds, and readers must not block on it. A cold concurrent caller may
    // probe twice, which is harmless.
    let shell = pick_user_shell()?;
    // The full environment probe already carries PATH, so reusing it saves a
    // second interactive shell startup and the rc-file work that comes with it.
    // Deliberately unforced: a forced refresh goes through
    // `reload_login_shell_environment`, which re-probes the variables first.
    // The dedicated probe stays as the fallback for a shell whose `env` has
    // neither `-0` nor usable output.
    let segments = match resolve_login_shell_variables(false)
        .await
        .and_then(|variables| variables.get("PATH").map(|path| split_path_segments(path)))
        .filter(|segments| !segments.is_empty())
    {
        Some(segments) => segments,
        None => hydrate_shell_path(&shell).await?,
    };
    *LOGIN_SHELL_PATH.write().await = Some(segments.clone());
    Some(segments)
}

async fn resolve_login_shell_variables(force: bool) -> Option<BTreeMap<String, String>> {
    if cfg!(windows) {
        return None;
    }
    if !force {
        if let Some(cached) = LOGIN_SHELL_VARIABLES.read().await.as_ref() {
            return Some(cached.clone());
        }
    }
    let shell = pick_user_shell()?;
    let variables = hydrate_shell_variables(&shell).await?;
    *LOGIN_SHELL_VARIABLES.write().await = Some(variables.clone());
    Some(variables)
}

/// One variable as the user's shell would see it.
///
/// The process environment wins: a value set explicitly for the host is a
/// deliberate override, and on Windows it is the only source there is.
pub(crate) async fn login_shell_variable(name: &str) -> Option<String> {
    if let Some(value) = env::var(name).ok().filter(|value| !value.is_empty()) {
        return Some(value);
    }
    login_shell_variables()
        .await?
        .get(name)
        .filter(|value| !value.is_empty())
        .cloned()
}

/// The environment a host-spawned tool should run with: the process
/// environment with the login shell's exports filling the gaps, and its PATH
/// merged in front.
pub(crate) async fn login_shell_command_environment() -> Option<BTreeMap<String, String>> {
    let mut environment = login_shell_variables().await?;
    environment.extend(env::vars());
    let merged = merged_path_value(
        environment.get("PATH").map(String::as_str),
        &login_shell_path_segments().await.unwrap_or_default(),
    );
    if let Some(path) = merged {
        environment.insert("PATH".to_string(), path);
    }
    Some(environment)
}

/// Login-shell PATH merged ahead of `existing`, or `None` when nothing changes.
pub(crate) async fn login_shell_merged_path(existing: Option<&str>) -> Option<String> {
    let segments = login_shell_path_segments().await?;
    merged_path_value(existing, &segments)
}

/// Give `command` the login-shell PATH so tools installed under a user prefix
/// (Homebrew, `~/.local/bin`, version managers) resolve by bare name.
pub(crate) async fn apply_login_shell_path(command: &mut Command) {
    let inherited = env::var("PATH").ok();
    if let Some(path) = login_shell_merged_path(inherited.as_deref()).await {
        command.env("PATH", path);
    }
}

/// Give `command` everything the user's login shell exports, PATH included,
/// with `overrides` applied last so a per-call value always wins.
///
/// A superset of [`apply_login_shell_path`]: use it wherever the spawned tool
/// reads its own configuration from the environment rather than only needing
/// to be found on disk.
pub(crate) async fn apply_login_shell_environment(
    command: &mut Command,
    overrides: &BTreeMap<String, String>,
) {
    if let Some(environment) = login_shell_variables().await {
        for (key, value) in environment {
            if env::var_os(&key).is_none() && !overrides.contains_key(&key) {
                command.env(key, value);
            }
        }
    }
    apply_login_shell_path(command).await;
    command.envs(overrides);
}

pub(crate) async fn setup_command_environment() -> Vec<(String, String)> {
    let mut environment = env::vars().collect::<Vec<_>>();
    if cfg!(windows) {
        return environment;
    }
    if let Some(segments) = login_shell_path_segments().await {
        merge_path_segments(&mut environment, &segments);
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

async fn hydrate_shell_variables(shell: &str) -> Option<BTreeMap<String, String>> {
    let command = format!(
        "printf '%s' '{delimiter}'; /usr/bin/env -0; printf '%s' '{delimiter}'",
        delimiter = SHELL_ENVIRONMENT_HYDRATION_DELIMITER,
    );
    let mut process = windowless_async_command(shell);
    process.args(["-ilc", &command]);
    let output = match timeout(SHELL_PATH_HYDRATION_TIMEOUT, process.output()).await {
        Ok(Ok(output)) => output,
        Ok(Err(_)) | Err(_) => return None,
    };
    let variables = parse_hydrated_shell_variables(&output.stdout);
    if variables.is_empty() {
        None
    } else {
        Some(variables)
    }
}

fn parse_hydrated_shell_variables(stdout: &[u8]) -> BTreeMap<String, String> {
    let Some(region) = delimited_region(stdout, SHELL_ENVIRONMENT_HYDRATION_DELIMITER) else {
        return BTreeMap::new();
    };
    // `env -0` is the reliable form, because a value may itself contain a
    // newline. BusyBox has no `-0` and prints newline-separated entries, so a
    // region without any NUL is parsed that way instead.
    let separator = if region.contains(&0) { 0 } else { b'\n' };
    region
        .split(|byte| *byte == separator)
        .filter_map(|entry| {
            let entry = String::from_utf8_lossy(entry);
            let (name, value) = entry.split_once('=')?;
            (!name.is_empty()).then(|| (name.to_string(), value.to_string()))
        })
        .collect()
}

fn delimited_region<'a>(stdout: &'a [u8], delimiter: &str) -> Option<&'a [u8]> {
    let marker = delimiter.as_bytes();
    let start = stdout
        .windows(marker.len())
        .position(|window| window == marker)?
        + marker.len();
    let end = stdout[start..]
        .windows(marker.len())
        .position(|window| window == marker)?;
    Some(&stdout[start..start + end])
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
    use super::{
        merge_path_segments, merged_path_value, parse_hydrated_shell_path,
        parse_hydrated_shell_variables,
    };

    #[test]
    fn parse_hydrated_shell_variables_reads_nul_separated_entries() {
        let stdout =
            b"rc noise__ALERA_SHELL_ENV__CCS_DIR=/home/user/.ccs\0PATH=/opt/bin\0__ALERA_SHELL_ENV__";

        let variables = parse_hydrated_shell_variables(stdout);

        assert_eq!(variables["CCS_DIR"], "/home/user/.ccs");
        assert_eq!(variables["PATH"], "/opt/bin");
        assert_eq!(variables.len(), 2);
    }

    #[test]
    fn parse_hydrated_shell_variables_keeps_newlines_inside_values() {
        let stdout = b"__ALERA_SHELL_ENV__KEY=line one\nline two\0OTHER=x\0__ALERA_SHELL_ENV__";

        let variables = parse_hydrated_shell_variables(stdout);

        assert_eq!(variables["KEY"], "line one\nline two");
        assert_eq!(variables["OTHER"], "x");
    }

    #[test]
    fn parse_hydrated_shell_variables_falls_back_to_newlines_without_nul_support() {
        let stdout =
            b"__ALERA_SHELL_ENV__CCS_DIR=/home/user/.ccs\nHOME=/home/user\n__ALERA_SHELL_ENV__";

        let variables = parse_hydrated_shell_variables(stdout);

        assert_eq!(variables["CCS_DIR"], "/home/user/.ccs");
        assert_eq!(variables["HOME"], "/home/user");
    }

    #[test]
    fn parse_hydrated_shell_variables_ignores_unmarked_output() {
        assert!(parse_hydrated_shell_variables(b"CCS_DIR=/nope").is_empty());
        assert!(parse_hydrated_shell_variables(b"__ALERA_SHELL_ENV__CCS_DIR=/nope").is_empty());
    }

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
