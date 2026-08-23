//! Splicing an agent's initial prompt into the launch it starts from.
//!
//! Which shape each agent accepts lives in `agent_registry`; this module turns
//! that declaration into argv tokens, and into the one line a Command-mode
//! profile becomes in the user's interactive shell.

use super::agent_profile_launch_snapshot::AgentInitialDeliveryMechanismV1;
#[cfg(test)]
use super::agent_registry::AgentAdapter;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ShellFamily {
    Posix,
    PowerShell,
    Cmd,
}

/// The standard end-of-options marker. Left unquoted when rendered, so the
/// launch line still reads the way the agent's own documentation writes it.
const OPTION_TERMINATOR: &str = "--";

/// The argv tokens the initial prompt contributes, in order.
///
/// Empty when the prompt never reaches the command line at launch.
#[cfg(test)]
pub fn initial_prompt_arguments(adapter: &AgentAdapter, prompt: &str) -> Vec<String> {
    initial_prompt_arguments_for(
        &AgentInitialDeliveryMechanismV1::from(adapter.startup_prompt),
        prompt,
    )
}

pub fn initial_prompt_arguments_for(
    mechanism: &AgentInitialDeliveryMechanismV1,
    prompt: &str,
) -> Vec<String> {
    match mechanism {
        AgentInitialDeliveryMechanismV1::PositionalAfterTerminator => {
            vec![OPTION_TERMINATOR.to_string(), prompt.to_string()]
        }
        AgentInitialDeliveryMechanismV1::Positional => vec![defuse_leading_dash(prompt)],
        AgentInitialDeliveryMechanismV1::LongOption { flag } => {
            vec![format!("{flag}={prompt}")]
        }
        AgentInitialDeliveryMechanismV1::StdinScript
        | AgentInitialDeliveryMechanismV1::TerminalAfterReady => Vec::new(),
    }
}

#[cfg(test)]
pub fn append_initial_prompt_argument(
    adapter: &AgentAdapter,
    arguments: &mut Vec<String>,
    prompt: &str,
) {
    arguments.extend(initial_prompt_arguments(adapter, prompt));
}

pub fn append_initial_prompt_argument_for(
    mechanism: &AgentInitialDeliveryMechanismV1,
    arguments: &mut Vec<String>,
    prompt: &str,
) {
    arguments.extend(initial_prompt_arguments_for(mechanism, prompt));
}

#[cfg(test)]
pub fn command_with_initial_prompt(
    adapter: &AgentAdapter,
    command: &str,
    prompt: &str,
    shell: &str,
) -> String {
    command_with_initial_prompt_for(
        &AgentInitialDeliveryMechanismV1::from(adapter.startup_prompt),
        command,
        prompt,
        shell,
    )
}

pub fn command_with_initial_prompt_for(
    mechanism: &AgentInitialDeliveryMechanismV1,
    command: &str,
    prompt: &str,
    shell: &str,
) -> String {
    let family = shell_family(shell);
    std::iter::once(command.trim().to_string())
        .chain(
            initial_prompt_arguments_for(mechanism, prompt)
                .into_iter()
                .map(|token| {
                    if token == OPTION_TERMINATOR {
                        token
                    } else {
                        quote_argument(&token, family)
                    }
                }),
        )
        .collect::<Vec<_>>()
        .join(" ")
}

/// A leading space, for the one agent with no way to end its own option list.
///
/// `pi` rejects `--` and reads `-anything` as an option, so a prompt opening
/// with a markdown bullet would abort the launch. The space is the smallest
/// change that keeps the instruction intact, and it is invisible to the model.
fn defuse_leading_dash(prompt: &str) -> String {
    if prompt.starts_with('-') {
        format!(" {prompt}")
    } else {
        prompt.to_string()
    }
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
    use super::super::agent_registry::adapter_for;
    use super::*;

    fn adapter(agent_type: &str) -> &'static AgentAdapter {
        adapter_for(agent_type).expect("known agent")
    }

    #[test]
    fn terminates_posix_options_before_a_dash_prefixed_prompt() {
        assert_eq!(
            command_with_initial_prompt(
                adapter("codex"),
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
            command_with_initial_prompt(
                adapter("codex"),
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
            command_with_initial_prompt(
                adapter("codex"),
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
        append_initial_prompt_argument(
            adapter("codex"),
            &mut arguments,
            "- Review memory\n- Implement it",
        );
        assert_eq!(
            arguments,
            ["--search", "--", "- Review memory\n- Implement it"]
        );
    }

    #[test]
    fn claude_and_cursor_take_the_same_terminated_positional() {
        for agent_type in ["claude", "cursor", "grok"] {
            assert_eq!(
                initial_prompt_arguments(adapter(agent_type), "- Ship it"),
                ["--", "- Ship it"],
                "{agent_type}"
            );
        }
    }

    #[test]
    fn long_option_agents_carry_the_prompt_in_one_token() {
        assert_eq!(
            initial_prompt_arguments(adapter("copilot"), "- Ship it"),
            ["--interactive=- Ship it"]
        );
        assert_eq!(
            initial_prompt_arguments(adapter("agy"), "- Ship it"),
            ["--prompt-interactive=- Ship it"]
        );
        assert_eq!(
            initial_prompt_arguments(adapter("opencode"), "- Ship it"),
            ["--prompt=- Ship it"]
        );
    }

    #[test]
    fn a_long_option_prompt_is_quoted_whole_so_it_stays_one_argument() {
        assert_eq!(
            command_with_initial_prompt(
                adapter("opencode"),
                "opencode --agent build",
                "- Review it\n- It's ready",
                "/bin/zsh"
            ),
            "opencode --agent build '--prompt=- Review it\n- It'\"'\"'s ready'"
        );
    }

    #[test]
    fn pi_gets_a_bare_positional_with_a_dash_prefix_defused() {
        assert_eq!(
            initial_prompt_arguments(adapter("pi"), "Ship it"),
            ["Ship it"]
        );
        assert_eq!(
            initial_prompt_arguments(adapter("pi"), "- Ship it"),
            [" - Ship it"]
        );
        assert_eq!(
            command_with_initial_prompt(
                adapter("pi"),
                "pi --thinking high",
                "- Ship it",
                "/bin/zsh"
            ),
            "pi --thinking high ' - Ship it'"
        );
    }

    #[test]
    fn amp_contributes_no_arguments_because_its_prompt_goes_to_stdin() {
        assert!(initial_prompt_arguments(adapter("amp"), "- Ship it").is_empty());
        assert_eq!(
            command_with_initial_prompt(adapter("amp"), "amp --mode high", "- Ship it", "/bin/zsh"),
            "amp --mode high"
        );
    }

    #[test]
    fn fx_contributes_no_arguments_until_its_ready_event() {
        assert!(initial_prompt_arguments(adapter("fx"), "- Ship it").is_empty());
        assert_eq!(
            command_with_initial_prompt(adapter("fx"), "fx", "- Ship it", "/bin/zsh"),
            "fx"
        );
    }
}
