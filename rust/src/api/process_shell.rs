//! The command line Alera hands to the platform shell.
//!
//! Every app-side spawn used to go through Dart's `runInShell: true`, and call
//! sites depend on what that buys: on Windows the shell is what resolves the
//! `.cmd`/`.bat` shims that `ollama`, `claude` or `npm` install, because
//! `CreateProcess` only ever appends `.exe`. The quoting rules below mirror
//! Dart's `_getShellArguments` so moving the spawn into Rust does not change
//! what any existing call site runs.

/// How a command reaches its shell. Windows needs a raw command line because
/// `cmd.exe` does not read the backslash escaping `std::process::Command`
/// applies to ordinary arguments.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) enum ShellInvocation {
    Posix {
        program: String,
        arguments: Vec<String>,
    },
    Windows {
        program: String,
        raw_arguments: String,
    },
}

pub(super) fn shell_invocation(executable: &str, arguments: &[String]) -> ShellInvocation {
    if cfg!(windows) {
        windows_shell_invocation(executable, arguments)
    } else {
        posix_shell_invocation(executable, arguments)
    }
}

pub(super) fn posix_shell_invocation(executable: &str, arguments: &[String]) -> ShellInvocation {
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
pub(super) fn windows_shell_invocation(executable: &str, arguments: &[String]) -> ShellInvocation {
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
