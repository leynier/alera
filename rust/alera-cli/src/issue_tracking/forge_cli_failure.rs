use serde_json::Value;

use super::{ForgeCliOutput, ForgeCliRunner, IssueFetchError};

/// How one forge CLI is named and fixed when it is missing or signed out.
pub(super) struct ForgeCli {
    pub program: &'static str,
    pub display: &'static str,
    pub install_hint: &'static str,
    pub auth_hint: &'static str,
}

/// Runs [cli] and returns its stdout parsed as JSON, classifying every
/// failure into an [IssueFetchError].
pub(super) async fn run_json(
    runner: &dyn ForgeCliRunner,
    cli: &ForgeCli,
    args: Vec<String>,
) -> Result<Value, IssueFetchError> {
    let output = match runner.run(cli.program, &args).await {
        Ok(output) => output,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Err(missing(cli));
        }
        Err(error) => return Err(IssueFetchError::Failed(error.to_string())),
    };
    if output.code != 0 {
        return Err(classify_failure(cli, &output));
    }
    serde_json::from_str(output.stdout.trim()).map_err(|_| {
        IssueFetchError::Failed(format!(
            "{} returned output Alera could not read.",
            cli.display
        ))
    })
}

fn missing(cli: &ForgeCli) -> IssueFetchError {
    IssueFetchError::CliMissing {
        cli: cli.display.to_string(),
        hint: cli.install_hint.to_string(),
    }
}

pub(super) fn classify_failure(cli: &ForgeCli, output: &ForgeCliOutput) -> IssueFetchError {
    let combined = format!("{}\n{}", output.stderr, output.stdout).to_ascii_lowercase();
    if output.code == 127
        || combined.contains("command not found")
        || combined.contains("is not recognized as")
        || combined.contains("no such file or directory")
        || combined.contains("az extension add")
        || combined.contains("is misspelled or not recognized")
    {
        return missing(cli);
    }
    if combined.contains("auth login")
        || combined.contains("az login")
        || combined.contains("not logged")
        || combined.contains("authentication")
        || combined.contains("unauthorized")
    {
        return IssueFetchError::NotAuthenticated {
            cli: cli.display.to_string(),
            hint: cli.auth_hint.to_string(),
        };
    }
    let message = first_meaningful_line(&output.stderr)
        .or_else(|| first_meaningful_line(&output.stdout))
        .unwrap_or_else(|| format!("{} exited with code {}.", cli.display, output.code));
    if combined.contains("could not resolve")
        || combined.contains("not found")
        || combined.contains("404")
        || combined.contains("does not exist")
    {
        return IssueFetchError::NotFound(message);
    }
    IssueFetchError::Failed(message)
}

fn first_meaningful_line(text: &str) -> Option<String> {
    text.lines()
        .map(str::trim)
        .find(|line| {
            !line.is_empty()
                && !line.eq_ignore_ascii_case("error")
                && !line.to_ascii_lowercase().contains("update available")
        })
        .map(ToOwned::to_owned)
}

pub(super) fn string_field(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|text| !text.is_empty())
        .map(ToOwned::to_owned)
}

pub(super) fn nested_string(value: &Value, key: &str, nested: &str) -> Option<String> {
    value.get(key).and_then(|inner| string_field(inner, nested))
}

pub(super) fn string_list(value: &Value, key: &str, nested: Option<&str>) -> Vec<String> {
    value
        .get(key)
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(|item| match nested {
                    Some(nested) => string_field(item, nested),
                    None => item.as_str().map(ToOwned::to_owned),
                })
                .collect()
        })
        .unwrap_or_default()
}

#[cfg(test)]
pub(crate) mod fake {
    use std::collections::VecDeque;
    use std::sync::Mutex;

    use async_trait::async_trait;

    use super::super::{ForgeCliOutput, ForgeCliRunner};

    /// Records each invocation and answers from a queue.
    #[derive(Default)]
    pub struct FakeForgeCliRunner {
        pub calls: Mutex<Vec<(String, Vec<String>)>>,
        responses: Mutex<VecDeque<std::io::Result<ForgeCliOutput>>>,
    }

    impl FakeForgeCliRunner {
        pub fn replying(code: i32, stdout: &str, stderr: &str) -> Self {
            let runner = Self::default();
            runner.push(Ok(ForgeCliOutput {
                code,
                stdout: stdout.to_string(),
                stderr: stderr.to_string(),
            }));
            runner
        }

        pub fn push(&self, response: std::io::Result<ForgeCliOutput>) {
            self.responses.lock().unwrap().push_back(response);
        }

        pub fn last_call(&self) -> (String, Vec<String>) {
            self.calls.lock().unwrap().last().cloned().expect("a call")
        }
    }

    #[async_trait]
    impl ForgeCliRunner for FakeForgeCliRunner {
        async fn run(&self, program: &str, args: &[String]) -> std::io::Result<ForgeCliOutput> {
            self.calls
                .lock()
                .unwrap()
                .push((program.to_string(), args.to_vec()));
            self.responses
                .lock()
                .unwrap()
                .pop_front()
                .expect("a queued response")
        }
    }
}
