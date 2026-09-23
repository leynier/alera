use std::io::Read;

use anyhow::{bail, Context, Result};
use clap::{ArgGroup, Args};

#[derive(Debug, Args)]
#[command(group(
    ArgGroup::new("prompt-source")
        .required(true)
        .multiple(false)
        .args(["prompt", "prompt_file", "prompt_stdin"])
))]
pub struct PromptSourceArgs {
    /// Prompt text delivered to the agent profile.
    #[arg(long, value_name = "text")]
    pub prompt: Option<String>,
    /// Read the prompt from a file.
    #[arg(long = "prompt-file", value_name = "path")]
    pub prompt_file: Option<String>,
    /// Read the prompt from standard input.
    #[arg(long = "prompt-stdin")]
    pub prompt_stdin: bool,
}

#[derive(Debug, Args)]
#[command(group(
    ArgGroup::new("spec-source")
        .required(true)
        .multiple(false)
        .args(["spec", "spec_file", "spec_stdin"])
))]
pub struct SpecSourceArgs {
    /// Task brief the dispatched worker receives.
    #[arg(long, value_name = "text")]
    pub spec: Option<String>,
    /// Read the task spec from a file.
    #[arg(long = "spec-file", value_name = "path")]
    pub spec_file: Option<String>,
    /// Read the task spec from standard input.
    #[arg(long = "spec-stdin")]
    pub spec_stdin: bool,
}

impl PromptSourceArgs {
    pub fn read(&self) -> Result<String> {
        read_required_text(
            self.prompt.clone(),
            self.prompt_file.as_deref(),
            self.prompt_stdin,
            "prompt",
        )
    }
}

impl SpecSourceArgs {
    pub fn read(&self) -> Result<String> {
        read_required_text(
            self.spec.clone(),
            self.spec_file.as_deref(),
            self.spec_stdin,
            "spec",
        )
    }
}

fn read_required_text(
    inline: Option<String>,
    file: Option<&str>,
    stdin: bool,
    label: &str,
) -> Result<String> {
    let raw = if let Some(inline) = inline {
        inline
    } else if let Some(path) = file {
        std::fs::read_to_string(path)
            .with_context(|| format!("could not read {label} file: {path}"))?
    } else if stdin {
        let mut body = String::new();
        std::io::stdin()
            .read_to_string(&mut body)
            .with_context(|| format!("could not read {label} from stdin"))?;
        body
    } else {
        bail!("{label} is required");
    };
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        bail!("{label} cannot be empty");
    }
    Ok(trimmed.to_string())
}

pub fn task_title_from_spec(spec: &str) -> String {
    let line = spec.lines().next().unwrap_or(spec).trim();
    const LIMIT: usize = 80;
    if line.chars().count() <= LIMIT {
        return line.to_string();
    }
    let truncated: String = line.chars().take(LIMIT.saturating_sub(3)).collect();
    format!("{truncated}...")
}

#[cfg(test)]
mod tests {
    use super::task_title_from_spec;

    #[test]
    fn task_title_uses_the_first_line_and_truncates() {
        assert_eq!(
            task_title_from_spec("Review tests\nMore detail"),
            "Review tests"
        );
        let long = "a".repeat(90);
        let title = task_title_from_spec(&long);
        assert_eq!(title.chars().count(), 80);
        assert!(title.ends_with("..."));
    }
}
