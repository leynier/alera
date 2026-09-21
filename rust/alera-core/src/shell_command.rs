//! The command line Alera hands to the platform shell when it runs a tool on
//! a user's behalf (`gh`, `az`, `ollama`, setup scripts).
//!
//! Every app-side spawn used to go through Dart's `runInShell: true`, and call
//! sites depend on what that buys: on Windows the shell is what resolves the
//! `.cmd`/`.bat` shims that `ollama`, `claude` or `npm` install, because
//! `CreateProcess` only ever appends `.exe`. The quoting rules below mirror
//! Dart's `_getShellArguments` so moving the spawn into Rust does not change
//! what any existing call site runs. The desktop bridge and the sidecar's
//! `host.process.run` both build their commands here, so a tool invoked for a
//! remote workspace runs exactly as it would have locally.

#[cfg(feature = "async-process")]
use std::collections::HashMap;

/// How a command reaches its shell. Windows needs a raw command line because
/// `cmd.exe` does not read the backslash escaping `std::process::Command`
/// applies to ordinary arguments.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ShellInvocation {
    Posix {
        program: String,
        arguments: Vec<String>,
    },
    Windows {
        program: String,
        raw_arguments: String,
    },
}

pub fn shell_invocation(executable: &str, arguments: &[String]) -> ShellInvocation {
    if cfg!(windows) {
        windows_shell_invocation(executable, arguments)
    } else {
        posix_shell_invocation(executable, arguments)
    }
}

pub fn posix_shell_invocation(executable: &str, arguments: &[String]) -> ShellInvocation {
    let mut line = single_quoted(executable);
    for argument in arguments {
        line.push(' ');
        line.push_str(&single_quoted(argument));
    }
    ShellInvocation::Posix {
        program: "/bin/sh".to_string(),
        arguments: vec!["-c".to_string(), line],
    }
}

/// `/d` skips AutoRun scripts, and `/s` makes `cmd.exe` strip the outer quotes
/// of the `/c` argument and take everything between them verbatim. That is what
/// lets each token carry its own quotes without further escaping.
pub fn windows_shell_invocation(executable: &str, arguments: &[String]) -> ShellInvocation {
    let mut line = String::from("/d /s /c \"");
    line.push_str(&double_quoted(executable));
    for argument in arguments {
        line.push(' ');
        line.push_str(&double_quoted(argument));
    }
    line.push('"');
    ShellInvocation::Windows {
        program: "cmd.exe".to_string(),
        raw_arguments: line,
    }
}

/// `'` cannot be escaped inside single quotes, so it is spliced in as a
/// double-quoted fragment: `'` + `"'"` + `'`.
fn single_quoted(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\"'\"'"))
}

fn double_quoted(value: &str) -> String {
    format!("\"{}\"", value.replace('"', "\\\""))
}

/// The async command for `executable arguments...` run through the platform
/// shell: windowless, in its own process group on unix (the shell does not
/// necessarily exec the tool, so killing the shell alone can leave the real
/// process holding the output pipes), with the parent environment kept unless
/// `include_parent_environment` is false.
#[cfg(feature = "async-process")]
pub fn shell_command(
    executable: &str,
    arguments: &[String],
    working_directory: Option<&str>,
    environment: Option<&HashMap<String, String>>,
    include_parent_environment: bool,
) -> tokio::process::Command {
    #[cfg(windows)]
    let executable = resolve_windows_executable(executable, working_directory, environment);
    #[cfg(not(windows))]
    let executable = executable.to_string();
    let mut command = match shell_invocation(&executable, arguments) {
        ShellInvocation::Posix { program, arguments } => {
            let mut command = crate::child_process::windowless_async_command(program);
            command.args(arguments);
            command
        }
        ShellInvocation::Windows {
            program,
            raw_arguments,
        } => {
            #[cfg_attr(not(windows), allow(unused_mut))]
            let mut command = crate::child_process::windowless_async_command(program);
            #[cfg(windows)]
            {
                command.raw_arg(&raw_arguments);
            }
            #[cfg(not(windows))]
            {
                let _ = raw_arguments;
            }
            command
        }
    };
    if let Some(working_directory) = working_directory {
        command.current_dir(working_directory);
    }
    if !include_parent_environment {
        command.env_clear();
    }
    if let Some(environment) = environment {
        command.envs(environment);
    }
    #[cfg(unix)]
    command.process_group(0);
    command.kill_on_drop(true);
    command
}

/// `cmd.exe /c` resolves a bare name against `PATH` and `PATHEXT` the same way
/// `CreateProcess` would, except that it also finds `.cmd` and `.bat` shims.
/// Resolving here first lets a call site that passed a working directory or an
/// explicit `PATH` see those honoured, since `cmd.exe` reads its own.
#[cfg(windows)]
fn resolve_windows_executable(
    executable: &str,
    working_directory: Option<&str>,
    environment: Option<&HashMap<String, String>>,
) -> String {
    if executable.contains(['/', '\\']) {
        return executable.to_string();
    }
    let environment_value = |name: &str| {
        environment
            .and_then(|values| {
                values
                    .iter()
                    .find(|(key, _)| key.eq_ignore_ascii_case(name))
                    .map(|(_, value)| value.clone())
            })
            .or_else(|| std::env::var(name).ok())
    };
    let extensions = if std::path::Path::new(executable).extension().is_some() {
        vec![String::new()]
    } else {
        environment_value("PATHEXT")
            .unwrap_or_else(|| ".COM;.EXE;.BAT;.CMD".to_string())
            .split(';')
            .filter(|extension| !extension.is_empty())
            .map(str::to_string)
            .collect()
    };
    let mut directories = Vec::new();
    if let Some(working_directory) = working_directory {
        directories.push(std::path::PathBuf::from(working_directory));
    } else if let Ok(current_directory) = std::env::current_dir() {
        directories.push(current_directory);
    }
    if let Some(path) = environment_value("PATH") {
        directories.extend(std::env::split_paths(&path));
    }
    for directory in directories {
        for extension in &extensions {
            let candidate = directory.join(format!("{executable}{extension}"));
            if candidate.is_file() {
                return candidate.to_string_lossy().into_owned();
            }
        }
    }
    executable.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(values: &[&str]) -> Vec<String> {
        values.iter().map(|value| value.to_string()).collect()
    }

    #[test]
    fn posix_invocation_single_quotes_every_token() {
        let invocation = posix_shell_invocation("gh", &args(&["pr", "list", "--json", "number"]));
        assert_eq!(
            invocation,
            ShellInvocation::Posix {
                program: "/bin/sh".to_string(),
                arguments: vec![
                    "-c".to_string(),
                    "'gh' 'pr' 'list' '--json' 'number'".to_string()
                ],
            }
        );
    }

    #[test]
    fn posix_invocation_splices_single_quotes() {
        let ShellInvocation::Posix { arguments, .. } =
            posix_shell_invocation("echo", &args(&["it's fine"]))
        else {
            panic!("expected a posix invocation");
        };
        assert_eq!(arguments[1], "'echo' 'it'\"'\"'s fine'");
    }

    #[test]
    fn windows_invocation_double_quotes_every_token() {
        let invocation = windows_shell_invocation("gh", &args(&["pr", "list"]));
        assert_eq!(
            invocation,
            ShellInvocation::Windows {
                program: "cmd.exe".to_string(),
                raw_arguments: "/d /s /c \"\"gh\" \"pr\" \"list\"\"".to_string(),
            }
        );
    }

    #[test]
    fn windows_invocation_escapes_embedded_double_quotes() {
        let ShellInvocation::Windows { raw_arguments, .. } =
            windows_shell_invocation("echo", &args(&[r#"he said "hi""#]))
        else {
            panic!("expected a windows invocation");
        };
        assert_eq!(
            raw_arguments,
            "/d /s /c \"\"echo\" \"he said \\\"hi\\\"\"\""
        );
    }

    #[test]
    fn windows_invocation_quotes_paths_with_spaces() {
        let ShellInvocation::Windows { raw_arguments, .. } =
            windows_shell_invocation(r"C:\Program Files\Git\bin\git.exe", &args(&["--version"]))
        else {
            panic!("expected a windows invocation");
        };
        assert_eq!(
            raw_arguments,
            "/d /s /c \"\"C:\\Program Files\\Git\\bin\\git.exe\" \"--version\"\""
        );
    }
}
