use std::path::Path;
use std::process::Stdio;
use std::time::Duration;

use alera_core::child_process::windowless_async_command;
use tokio::io::{AsyncRead, AsyncReadExt as _};

use super::contract::{EmulatorFailure, EmulatorResult};

const COMMAND_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_OUTPUT_BYTES: usize = 16 * 1024 * 1024;

pub async fn output(
    program: impl AsRef<Path>,
    args: &[String],
    operation: &str,
) -> EmulatorResult<std::process::Output> {
    output_with_timeout(program, args, operation, COMMAND_TIMEOUT).await
}

pub async fn output_with_timeout(
    program: impl AsRef<Path>,
    args: &[String],
    operation: &str,
    timeout: Duration,
) -> EmulatorResult<std::process::Output> {
    let mut command = windowless_async_command(program.as_ref());
    command
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    let mut child = command.spawn().map_err(|error| {
        EmulatorFailure::dependency(
            program.as_ref().to_string_lossy().as_ref(),
            format!("{operation} could not start: {error}"),
        )
    })?;
    let stdout = child
        .stdout
        .take()
        .expect("emulator command stdout was configured as piped");
    let stderr = child
        .stderr
        .take()
        .expect("emulator command stderr was configured as piped");
    let result = tokio::time::timeout(timeout, async {
        tokio::try_join!(child.wait(), read_capped(stdout), read_capped(stderr),)
    })
    .await
    .map_err(|_| {
        EmulatorFailure::new(
            "operation_timeout",
            format!("{operation} timed out."),
            ["Retry after the emulator finishes booting."],
        )
    })?;
    let (status, stdout, stderr) = result.map_err(|error| {
        if error.kind() == std::io::ErrorKind::InvalidData {
            EmulatorFailure::new(
                "provider_incompatible",
                format!("{operation} returned more output than Alera can safely retain."),
                ["Retry with narrower filters."],
            )
        } else {
            EmulatorFailure::dependency(
                program.as_ref().to_string_lossy().as_ref(),
                format!("{operation} failed while reading its output: {error}"),
            )
        }
    })?;
    let result = std::process::Output {
        status,
        stdout,
        stderr,
    };
    if result.status.success() {
        return Ok(result);
    }
    let stderr = String::from_utf8_lossy(&result.stderr).trim().to_string();
    let stdout = String::from_utf8_lossy(&result.stdout).trim().to_string();
    Err(EmulatorFailure::new(
        "provider_incompatible",
        format!(
            "{operation} failed: {}",
            if stderr.is_empty() { stdout } else { stderr }
        ),
        ["Verify the selected virtual device and host SDK, then retry."],
    ))
}

async fn read_capped(mut reader: impl AsyncRead + Unpin) -> std::io::Result<Vec<u8>> {
    let mut output = Vec::new();
    let mut buffer = [0_u8; 8192];
    loop {
        let read = reader.read(&mut buffer).await?;
        if read == 0 {
            return Ok(output);
        }
        if output.len().saturating_add(read) > MAX_OUTPUT_BYTES {
            return Err(std::io::Error::from(std::io::ErrorKind::InvalidData));
        }
        output.extend_from_slice(&buffer[..read]);
    }
}

pub fn strings(values: &[&str]) -> Vec<String> {
    values.iter().map(|value| (*value).to_string()).collect()
}
