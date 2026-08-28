#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ShellFamily {
    Posix,
    PowerShell,
    Cmd,
}

// Codex parses a leading dash in its positional prompt as another option unless
// the standard option terminator appears first.
const CODEX_OPTION_TERMINATOR: &str = "--";

pub fn codex_command_with_initial_prompt(command: &str, prompt: &str, shell: &str) -> String {
    format!(
        "{} {} {}",
        command.trim(),
        CODEX_OPTION_TERMINATOR,
        quote_argument(prompt, shell_family(shell))
    )
}

pub fn append_codex_initial_prompt_argument(arguments: &mut Vec<String>, prompt: String) {
    arguments.push(CODEX_OPTION_TERMINATOR.to_string());
    arguments.push(prompt);
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
    fn terminates_posix_options_before_a_dash_prefixed_prompt() {
        assert_eq!(
            codex_command_with_initial_prompt(
                "codex --search",
                "- Review $HOME\n- It's ready",
                "/bin/zsh"
            ),
            "codex --search -- '- Review $HOME\n- It'\"'\"'s ready'"
        );
    }

    #[test]
    fn terminates_powershell_options_before_a_dash_prefixed_prompt() {
        assert_eq!(
            codex_command_with_initial_prompt(
                "codex --search",
                "- Review memory\n- It's ready",
                "pwsh.exe"
            ),
            "codex --search -- '- Review memory\n- It''s ready'"
        );
    }

    #[test]
    fn terminates_cmd_options_before_a_dash_prefixed_prompt() {
        assert_eq!(
            codex_command_with_initial_prompt(
                "codex --search",
                "- Review \"context\"\n- Implement memory",
                "C:\\Windows\\cmd.exe"
            ),
            "codex --search -- \"- Review \"\"context\"\"\n- Implement memory\""
        );
    }

    #[test]
    fn appends_the_option_terminator_before_a_managed_prompt() {
        let mut arguments = vec!["--search".to_string()];
        append_codex_initial_prompt_argument(
            &mut arguments,
            "- Review memory\n- Implement it".to_string(),
        );
        assert_eq!(arguments, ["--search", "--", "- Review memory\n- Implement it"]);
    }
}
