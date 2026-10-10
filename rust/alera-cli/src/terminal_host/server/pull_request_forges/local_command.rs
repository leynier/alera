//! The process a forge CLI (`glab`, `az`) runs as on this machine.
//!
//! On unix it goes through `alera_core::shell_command`, whose `/bin/sh -c`
//! line single-quotes every token, so nothing in an argument is reinterpreted.
//! On Windows that helper builds a `cmd.exe /c` line whose `\"` escaping
//! `cmd.exe` does not honour, so `&`, `|` or `%VAR%` in an argument would run
//! or expand. The CLI is spawned directly there instead: the name is resolved
//! against `PATH` and `PATHEXT` (what `cmd.exe` did for the `.cmd` shim that
//! `az` installs), and the standard library quotes the arguments, applying its
//! batch-file escaping, or refusing an argument it cannot pass safely, when the
//! target is a `.cmd` or `.bat`. Unlike `cmd.exe`, the checkout itself is never
//! searched, so a repository cannot plant its own `glab.cmd`.

use std::collections::HashMap;
#[cfg(any(windows, test))]
use std::path::{Path, PathBuf};

pub(super) fn forge_command(
    program: &str,
    args: &[String],
    cwd: &str,
    environment: &HashMap<String, String>,
) -> tokio::process::Command {
    #[cfg(windows)]
    {
        let lookup = |name: &str| {
            environment
                .iter()
                .find(|(key, _)| key.eq_ignore_ascii_case(name))
                .map(|(_, value)| value.clone())
                .or_else(|| std::env::var(name).ok())
        };
        let resolved = resolve_on_path(
            program,
            lookup("PATH").as_deref(),
            lookup("PATHEXT").as_deref(),
            |candidate| candidate.is_file(),
        );
        let mut command = alera_core::child_process::windowless_async_command(resolved);
        command
            .args(args)
            .current_dir(cwd)
            .envs(environment)
            .kill_on_drop(true);
        command
    }
    #[cfg(not(windows))]
    {
        alera_core::shell_command::shell_command(program, args, Some(cwd), Some(environment), true)
    }
}

/// The first `PATH` entry holding [program] with one of the `PATHEXT`
/// extensions. A name with a directory, or one that is not found, is
/// returned unchanged, so a missing CLI still fails to start.
#[cfg(any(windows, test))]
fn resolve_on_path(
    program: &str,
    path: Option<&str>,
    path_extensions: Option<&str>,
    is_file: impl Fn(&Path) -> bool,
) -> PathBuf {
    if program.contains(['/', '\\']) {
        return PathBuf::from(program);
    }
    let extensions = if Path::new(program).extension().is_some() {
        vec![String::new()]
    } else {
        path_extensions
            .unwrap_or(".COM;.EXE;.BAT;.CMD")
            .split(';')
            .filter(|extension| !extension.is_empty())
            .map(str::to_string)
            .collect()
    };
    let directories = path
        .unwrap_or_default()
        .split(';')
        .map(|directory| directory.trim().trim_matches('"'))
        .filter(|directory| !directory.is_empty());
    for directory in directories {
        for extension in &extensions {
            let candidate = Path::new(directory).join(format!("{program}{extension}"));
            if is_file(&candidate) {
                return candidate;
            }
        }
    }
    PathBuf::from(program)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_the_cmd_shim_from_path_and_never_the_checkout() {
        let shim = Path::new("bin").join("az.CMD");
        let planted = Path::new("repo").join("az.CMD");
        let present = |candidate: &Path| candidate == shim || candidate == planted;
        assert_eq!(
            resolve_on_path("az", Some("\"bin\";other"), Some(".EXE;.CMD"), present),
            shim
        );
        assert_eq!(
            resolve_on_path("az", Some("other"), Some(".EXE;.CMD"), present),
            PathBuf::from("az"),
            "an unresolved name stays bare, so the spawn fails as missing"
        );
        assert_eq!(
            resolve_on_path(r"C:\tools\glab.exe", Some("bin"), None, present),
            PathBuf::from(r"C:\tools\glab.exe")
        );
        let glab = Path::new("bin").join("glab.exe");
        assert_eq!(
            resolve_on_path("glab.exe", Some("bin"), None, |candidate| candidate == glab),
            glab
        );
    }
}
