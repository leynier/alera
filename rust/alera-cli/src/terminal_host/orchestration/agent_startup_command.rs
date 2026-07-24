#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ShellFamily {
    Posix,
    PowerShell,
    Cmd,
}

pub fn command_with_initial_prompt(command: &str, prompt: &str, shell: &str) -> String {
    format!(
        "{} {}",
        command.trim(),
        quote_argument(prompt, shell_family(shell))
    )
}

fn shell_family(shell: &str) -> ShellFamily {
    let normalized = shell.replace('\\', "/").to_ascii_lowercase();
    let executable = normalized.rsplit('/').next().unwrap_or(&normalized);
    if executable == "powershell"
        || executable == "powershell.exe"
        || executable == "pwsh"
        || executable == "pwsh.exe"
    {
        ShellFamily::PowerShell
    } else if executable == "cmd" || executable == "cmd.exe" {
        ShellFamily::Cmd
    } else {
        ShellFamily::Posix
    }
}

fn quote_argument(value: &str, family: ShellFamily) -> String {
    match family {
        ShellFamily::Posix => format!("'{}'", value.replace('\'', "'\"'\"'")),
        ShellFamily::PowerShell => format!("'{}'", value.replace('\'', "''")),
        ShellFamily::Cmd => format!("\"{}\"", value.replace('"', "\"\"")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quotes_posix_prompt_without_shell_expansion() {
        assert_eq!(
            command_with_initial_prompt("codex", "read $HOME and it's ready", "/bin/zsh"),
            "codex 'read $HOME and it'\"'\"'s ready'"
        );
    }

    #[test]
    fn quotes_powershell_prompt() {
        assert_eq!(
            command_with_initial_prompt("codex", "it's ready", "pwsh.exe"),
            "codex 'it''s ready'"
        );
    }

    #[test]
    fn quotes_cmd_prompt() {
        assert_eq!(
            command_with_initial_prompt("codex", "read \"context\"", "C:\\Windows\\cmd.exe"),
            "codex \"read \"\"context\"\"\""
        );
    }
}
