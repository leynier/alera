use alera_core::child_process::windowless_async_command;
use alera_core::runtime::{WorktreeSetupStepKind, WorktreeSetupStepReport};
use std::process::Stdio;
use tokio::io::AsyncReadExt;

const SETUP_OUTPUT_TAIL_BYTES: usize = 16 * 1024;

pub(crate) async fn run_setup_command(
    workspace_path: &str,
    command: &str,
    environment: &[(String, String)],
    journal: Option<crate::relocation_setup_process::SetupProcessJournal<'_>>,
) -> WorktreeSetupStepReport {
    let mut record = if let Some(journal) = &journal {
        match journal.begin().await {
            Ok(record) => Some(record),
            Err(error) => return command_error_report(command, &error.to_string()),
        }
    } else {
        None
    };
    let (executable, args) = shell_invocation(command);
    let mut child = match windowless_async_command(executable)
        .args(args)
        .current_dir(workspace_path)
        .envs(environment.iter().map(|(key, value)| (key, value)))
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(child) => child,
        Err(error) => {
            if let (Some(journal), Some(record)) = (&journal, &record) {
                if let Err(record_error) = journal
                    .ended(
                        record,
                        alera_core::runtime::SetupRootProcessPhase::SpawnFailed,
                    )
                    .await
                {
                    return command_error_report(
                        command,
                        &format!("{error}; could not record the failed spawn: {record_error}"),
                    );
                }
            }
            return command_error_report(command, &error.to_string());
        }
    };
    let mut recording_error = None;
    if let (Some(journal), Some(previous)) = (&journal, &record) {
        if let Some(pid) = child.id() {
            match journal.spawned(previous, pid).await {
                Ok(started) => record = Some(started),
                Err(error) => recording_error = Some(error.to_string()),
            }
        } else {
            recording_error = Some("The spawned setup process has no available PID".into());
        }
    }
    let mut stdout_tail = child
        .stdout
        .take()
        .map(|stdout| tokio::spawn(read_bounded_tail(stdout)));
    let mut stderr_tail = child
        .stderr
        .take()
        .map(|stderr| tokio::spawn(read_bounded_tail(stderr)));
    match crate::setup_process_cancellation::wait(&mut child, journal.as_ref(), record.as_ref())
        .await
    {
        Ok(waited) => {
            let status = waited.status;
            if recording_error.is_none() {
                if let (Some(journal), Some(record)) = (&journal, &mut record) {
                    if let Err(error) = journal
                        .ended(
                            record,
                            alera_core::runtime::SetupRootProcessPhase::RootExitedOutputPending,
                        )
                        .await
                    {
                        recording_error = Some(error.to_string());
                    } else {
                        record.phase =
                            alera_core::runtime::SetupRootProcessPhase::RootExitedOutputPending;
                    }
                }
            }
            let (stdout, stderr, drain_error) = drain_output(
                &mut stdout_tail,
                &mut stderr_tail,
                journal
                    .is_some()
                    .then_some(std::time::Duration::from_secs(5)),
            )
            .await;
            if recording_error.is_none() && drain_error.is_none() {
                if let (Some(journal), Some(record)) = (&journal, &record) {
                    if let Err(error) = journal
                        .ended(
                            record,
                            alera_core::runtime::SetupRootProcessPhase::RootExited,
                        )
                        .await
                    {
                        recording_error = Some(error.to_string());
                    }
                }
            }
            recording_error = recording_error.or(drain_error).or(waited.closure_error);
            let code = status.code().unwrap_or(-1) as i64;
            WorktreeSetupStepReport {
                kind: WorktreeSetupStepKind::Command,
                label: command.to_string(),
                succeeded: status.success() && recording_error.is_none(),
                message: if let Some(error) = recording_error {
                    Some(format!(
                        "Setup process result could not be persisted: {error}"
                    ))
                } else if status.success() {
                    None
                } else {
                    Some(format!("Command exited with code {code}"))
                },
                exit_code: Some(code),
                stdout_tail: stdout,
                stderr_tail: stderr,
            }
        }
        Err(error) => {
            abort_output(&stdout_tail, &stderr_tail);
            WorktreeSetupStepReport {
                kind: WorktreeSetupStepKind::Command,
                label: command.to_string(),
                succeeded: false,
                message: Some(error.to_string()),
                exit_code: None,
                stdout_tail: None,
                stderr_tail: None,
            }
        }
    }
}

fn command_error_report(command: &str, message: &str) -> WorktreeSetupStepReport {
    WorktreeSetupStepReport {
        kind: WorktreeSetupStepKind::Command,
        label: command.into(),
        succeeded: false,
        message: Some(message.into()),
        exit_code: None,
        stdout_tail: None,
        stderr_tail: None,
    }
}

type OutputTask = Option<tokio::task::JoinHandle<std::io::Result<Option<String>>>>;

fn abort_output(stdout: &OutputTask, stderr: &OutputTask) {
    for handle in [stdout, stderr].into_iter().flatten() {
        handle.abort();
    }
}

async fn await_tail(handle: &mut OutputTask) -> Result<Option<String>, String> {
    match handle.as_mut() {
        Some(handle) => handle
            .await
            .map_err(|error| error.to_string())?
            .map_err(|error| error.to_string()),
        None => Ok(None),
    }
}

async fn drain_output(
    stdout: &mut OutputTask,
    stderr: &mut OutputTask,
    deadline: Option<std::time::Duration>,
) -> (Option<String>, Option<String>, Option<String>) {
    let drain = async { tokio::try_join!(await_tail(stdout), await_tail(stderr)) };
    let result = if let Some(deadline) = deadline {
        tokio::time::timeout(deadline, drain)
            .await
            .unwrap_or_else(|_| {
                Err("Setup output closure could not be verified before its deadline".into())
            })
    } else {
        drain.await
    };
    match result {
        Ok((stdout, stderr)) => (stdout, stderr, None),
        Err(error) => {
            abort_output(stdout, stderr);
            (None, None, Some(error))
        }
    }
}

async fn read_bounded_tail<R>(mut reader: R) -> std::io::Result<Option<String>>
where
    R: tokio::io::AsyncRead + Unpin + Send + 'static,
{
    let mut tail = BoundedOutputTail::default();
    let mut buffer = [0_u8; 8192];
    loop {
        match reader.read(&mut buffer).await {
            Ok(0) => break,
            Ok(count) => tail.push(&buffer[..count]),
            Err(error) => return Err(error),
        }
    }
    Ok(tail.value())
}

#[derive(Default)]
struct BoundedOutputTail {
    bytes: Vec<u8>,
}

impl BoundedOutputTail {
    fn push(&mut self, chunk: &[u8]) {
        self.bytes.extend_from_slice(chunk);
        if self.bytes.len() > SETUP_OUTPUT_TAIL_BYTES {
            let excess = self.bytes.len() - SETUP_OUTPUT_TAIL_BYTES;
            self.bytes.drain(0..excess);
        }
    }

    fn value(self) -> Option<String> {
        text_tail(&self.bytes)
    }
}

fn shell_invocation(command: &str) -> (&'static str, Vec<String>) {
    if cfg!(windows) {
        (
            "cmd.exe",
            vec![
                "/d".to_string(),
                "/s".to_string(),
                "/c".to_string(),
                command.to_string(),
            ],
        )
    } else {
        ("/bin/sh", vec!["-c".to_string(), command.to_string()])
    }
}

fn text_tail(bytes: &[u8]) -> Option<String> {
    let text = String::from_utf8_lossy(bytes).trim().to_string();
    if text.is_empty() {
        return None;
    }
    const MAX_CHARS: usize = 4000;
    if text.chars().count() <= MAX_CHARS {
        return Some(text);
    }
    let mut chars = text.chars().rev().take(MAX_CHARS).collect::<Vec<_>>();
    chars.reverse();
    Some(chars.into_iter().collect())
}

#[cfg(test)]
mod tests {
    use super::{drain_output, read_bounded_tail, text_tail};

    #[tokio::test]
    async fn unclosed_output_times_out_and_releases_the_reader() {
        let (reader, _writer) = tokio::io::duplex(16);
        let mut stdout = Some(tokio::spawn(read_bounded_tail(reader)));
        let mut stderr = None;
        let (_, _, error) = drain_output(
            &mut stdout,
            &mut stderr,
            Some(std::time::Duration::from_millis(10)),
        )
        .await;
        assert!(error.unwrap().contains("could not be verified"));
        assert!(stdout.take().unwrap().await.unwrap_err().is_cancelled());
    }

    #[tokio::test]
    async fn read_failure_is_not_treated_as_confirmed_output_closure() {
        let (reader, _writer) = tokio::io::duplex(16);
        let mut stdout = Some(tokio::spawn(read_bounded_tail(reader)));
        let mut stderr = Some(tokio::spawn(async {
            Err(std::io::Error::other("fixture read failed"))
        }));
        let (_, _, error) = drain_output(&mut stdout, &mut stderr, None).await;
        assert_eq!(error.as_deref(), Some("fixture read failed"));
        assert!(stdout.take().unwrap().await.unwrap_err().is_cancelled());
    }

    #[test]
    fn text_tail_keeps_unicode_boundaries() {
        let input = format!("{}{}", "a".repeat(4001), "ñ");
        let tail = text_tail(input.as_bytes()).unwrap();

        assert!(tail.starts_with('a'));
        assert!(tail.ends_with('ñ'));
        assert_eq!(tail.chars().count(), 4000);
    }

    #[test]
    fn text_tail_trims_empty_output() {
        assert_eq!(text_tail(b" \n\t "), None);
    }
}
