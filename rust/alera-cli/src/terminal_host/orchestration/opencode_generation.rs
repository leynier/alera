//! Which OpenCode generation `opencode` launches on this host.
//!
//! OpenCode v1 (`opencode-ai`) and OpenCode 2 (`@opencode/cli`) both install
//! as `opencode`, and a v1 install stays on v1 until the user runs
//! `opencode upgrade --major`. Their launch lines cannot be shared: both CLIs
//! reject flags they do not know, v2 needs `--standalone` to give the tab a
//! private server, and only v1 takes `--model`/`--agent` on the TUI or
//! `--variant` on `run`. The answer comes from `opencode --version` (`1.19.4`
//! on v1, `opencode v2.1.4` on v2), probed off the actor and cached by the
//! resolved executable's path, size and modification time, so an upgrade is
//! picked up by the launch after the one that noticed it.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::{Duration, SystemTime};

const EXECUTABLE: &str = "opencode";
const PROBE_TIMEOUT: Duration = Duration::from_secs(5);
/// Forces a generation (`1` or `2`) without probing, for tests and for a host
/// whose `opencode` cannot answer `--version`.
pub const GENERATION_OVERRIDE_ENV: &str = "ALERA_OPENCODE_GENERATION";

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum OpenCodeGeneration {
    V1,
    /// The generation upstream ships today, used until a probe says otherwise.
    #[default]
    V2,
}

impl OpenCodeGeneration {
    pub fn from_version_output(output: &str) -> Option<Self> {
        let version = output
            .split_whitespace()
            .find(|token| {
                token
                    .trim_start_matches('v')
                    .starts_with(|c: char| c.is_ascii_digit())
            })?
            .trim_start_matches('v');
        match version.split('.').next()?.parse::<u64>().ok()? {
            0 | 1 => Some(Self::V1),
            _ => Some(Self::V2),
        }
    }

    fn from_override(value: &str) -> Option<Self> {
        match value.trim() {
            "1" | "v1" => Some(Self::V1),
            "2" | "v2" => Some(Self::V2),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct Fingerprint {
    path: PathBuf,
    len: u64,
    modified: Option<SystemTime>,
}

struct Probe {
    fingerprint: Fingerprint,
    generation: OpenCodeGeneration,
}

static CACHE: Mutex<Option<Probe>> = Mutex::new(None);
static REFRESHING: AtomicBool = AtomicBool::new(false);

/// The generation to launch now. Never blocks: it answers from the cache (or
/// the default when nothing was probed yet) and refreshes in the background.
pub fn current() -> OpenCodeGeneration {
    if let Some(generation) = overridden() {
        return generation;
    }
    spawn_refresh();
    CACHE
        .lock()
        .ok()
        .and_then(|cache| cache.as_ref().map(|probe| probe.generation))
        .unwrap_or_default()
}

/// Re-checks the installed `opencode` on the current tokio runtime, if any.
/// A refresh already in flight absorbs the request.
pub fn spawn_refresh() {
    // Unit tests share one process, so a probe of the developer's own
    // `opencode` must not leak into the launches other tests assert.
    if cfg!(test) || overridden().is_some() {
        return;
    }
    let Ok(handle) = tokio::runtime::Handle::try_current() else {
        return;
    };
    if REFRESHING.swap(true, Ordering::AcqRel) {
        return;
    }
    handle.spawn(async {
        refresh().await;
        REFRESHING.store(false, Ordering::Release);
    });
}

fn overridden() -> Option<OpenCodeGeneration> {
    std::env::var(GENERATION_OVERRIDE_ENV)
        .ok()
        .and_then(|value| OpenCodeGeneration::from_override(&value))
}

async fn refresh() {
    let environment = crate::login_shell_environment::login_shell_command_environment()
        .await
        .unwrap_or_else(|| std::env::vars().collect());
    let lookup = environment.clone();
    let fingerprint = tokio::task::spawn_blocking(move || fingerprint(&lookup))
        .await
        .ok()
        .flatten();
    let Some(fingerprint) = fingerprint else {
        if let Ok(mut cache) = CACHE.lock() {
            *cache = None;
        }
        return;
    };
    let unchanged = CACHE.lock().ok().is_some_and(|cache| {
        cache
            .as_ref()
            .is_some_and(|probe| probe.fingerprint == fingerprint)
    });
    if unchanged {
        return;
    }
    let generation = probe(&fingerprint.path, &environment)
        .await
        .unwrap_or_default();
    if let Ok(mut cache) = CACHE.lock() {
        *cache = Some(Probe {
            fingerprint,
            generation,
        });
    }
}

async fn probe(
    executable: &Path,
    environment: &BTreeMap<String, String>,
) -> Option<OpenCodeGeneration> {
    let mut command = alera_core::child_process::windowless_async_command(executable);
    command
        .arg("--version")
        .envs(environment)
        .current_dir(std::env::temp_dir())
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    let output = tokio::time::timeout(PROBE_TIMEOUT, command.output())
        .await
        .ok()?
        .ok()?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    OpenCodeGeneration::from_version_output(&stdout)
        .or_else(|| OpenCodeGeneration::from_version_output(&stderr))
}

fn fingerprint(environment: &BTreeMap<String, String>) -> Option<Fingerprint> {
    let path = resolve_executable(
        environment
            .get("PATH")
            .map(String::as_str)
            .unwrap_or_default(),
        environment.get("PATHEXT").map(String::as_str),
        cfg!(windows),
    )?;
    let metadata = std::fs::metadata(&path).ok()?;
    Some(Fingerprint {
        path,
        len: metadata.len(),
        modified: metadata.modified().ok(),
    })
}

/// The first `PATH` entry holding `opencode`, trying the `PATHEXT` extensions
/// on Windows, where npm and bun install a `.cmd` or `.exe` shim.
fn resolve_executable(path: &str, path_extensions: Option<&str>, windows: bool) -> Option<PathBuf> {
    let extensions: Vec<String> = if windows {
        path_extensions
            .unwrap_or(".COM;.EXE;.BAT;.CMD")
            .split(';')
            .filter(|extension| !extension.is_empty())
            .map(str::to_string)
            .collect()
    } else {
        vec![String::new()]
    };
    std::env::split_paths(path)
        .filter(|directory| directory.is_absolute())
        .flat_map(|directory| {
            extensions
                .iter()
                .map(move |extension| directory.join(format!("{EXECUTABLE}{extension}")))
        })
        .find(|candidate| candidate.is_file())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_version_output_names_the_generation() {
        assert_eq!(
            OpenCodeGeneration::from_version_output("1.19.4\n"),
            Some(OpenCodeGeneration::V1)
        );
        assert_eq!(
            OpenCodeGeneration::from_version_output("0.15.8"),
            Some(OpenCodeGeneration::V1)
        );
        assert_eq!(
            OpenCodeGeneration::from_version_output("opencode v2.1.4\n"),
            Some(OpenCodeGeneration::V2)
        );
        assert_eq!(
            OpenCodeGeneration::from_version_output("3.0.0-beta.1"),
            Some(OpenCodeGeneration::V2)
        );
        assert_eq!(OpenCodeGeneration::from_version_output(""), None);
        assert_eq!(
            OpenCodeGeneration::from_version_output("command not found"),
            None
        );
    }

    #[test]
    fn an_override_accepts_both_spellings() {
        assert_eq!(
            OpenCodeGeneration::from_override(" 1 "),
            Some(OpenCodeGeneration::V1)
        );
        assert_eq!(
            OpenCodeGeneration::from_override("v2"),
            Some(OpenCodeGeneration::V2)
        );
        assert_eq!(OpenCodeGeneration::from_override("latest"), None);
    }

    #[test]
    fn resolution_finds_the_first_executable_on_path() {
        let first = tempfile::tempdir().unwrap();
        let second = tempfile::tempdir().unwrap();
        let shim = second.path().join("opencode");
        std::fs::write(&shim, "").unwrap();
        let path = std::env::join_paths([first.path(), second.path()]).unwrap();
        assert_eq!(
            resolve_executable(path.to_str().unwrap(), None, false),
            Some(shim)
        );
        assert_eq!(
            resolve_executable(first.path().to_str().unwrap(), None, false),
            None
        );
    }

    #[test]
    fn windows_resolution_tries_the_path_extensions() {
        let directory = tempfile::tempdir().unwrap();
        let shim = directory.path().join("opencode.CMD");
        std::fs::write(&shim, "").unwrap();
        assert_eq!(
            resolve_executable(directory.path().to_str().unwrap(), Some(".EXE;.CMD"), true),
            Some(shim)
        );
    }
}
