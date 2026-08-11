use std::path::Path;
use std::process::Stdio;
use std::time::Duration;

use alera_core::child_process::windowless_async_command;
use tokio::io::{AsyncRead, AsyncReadExt as _};

use super::super::accessibility::MAX_AX_INPUT_BYTES;
use super::super::contract::{EmulatorFailure, EmulatorResult};

const ACCESSIBILITY_TIMEOUT: Duration = Duration::from_secs(30);

pub async fn dump(adb: &Path, serial: &str) -> EmulatorResult<Vec<u8>> {
    let mut command = windowless_async_command(adb);
    command
        .args(["-s", serial, "exec-out", "uiautomator", "dump", "/dev/tty"])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    let mut child = command.spawn().map_err(|error| {
        EmulatorFailure::dependency(
            adb.to_string_lossy().as_ref(),
            format!("Android accessibility snapshot could not start: {error}"),
        )
    })?;
    let stdout = child
        .stdout
        .take()
        .expect("uiautomator stdout was configured as piped");
    let stderr = child
        .stderr
        .take()
        .expect("uiautomator stderr was configured as piped");
    let result = tokio::time::timeout(ACCESSIBILITY_TIMEOUT, async {
        tokio::try_join!(child.wait(), read_capped(stdout), read_capped(stderr),)
    })
    .await
    .map_err(|_| {
        EmulatorFailure::new(
            "operation_timeout",
            "Android accessibility snapshot timed out.",
            ["Retry after the visible screen settles."],
        )
    })?;
    let (status, stdout, _) = result.map_err(|error| {
        if error.kind() == std::io::ErrorKind::InvalidData {
            EmulatorFailure::new(
                "provider_incompatible",
                "Android accessibility returned more than 1 MiB of output.",
                ["Simplify the visible screen and retry the snapshot."],
            )
        } else {
            EmulatorFailure::dependency(
                adb.to_string_lossy().as_ref(),
                format!("Android accessibility output could not be read: {error}"),
            )
        }
    })?;
    if !status.success() {
        return Err(EmulatorFailure::new(
            "provider_incompatible",
            format!("Android accessibility snapshot failed with status {status}."),
            ["Retry after the visible screen settles."],
        ));
    }
    Ok(stdout)
}

async fn read_capped(mut reader: impl AsyncRead + Unpin) -> std::io::Result<Vec<u8>> {
    let mut output = Vec::new();
    let mut buffer = [0_u8; 8192];
    loop {
        let read = reader.read(&mut buffer).await?;
        if read == 0 {
            return Ok(output);
        }
        if output.len().saturating_add(read) > MAX_AX_INPUT_BYTES {
            return Err(std::io::Error::from(std::io::ErrorKind::InvalidData));
        }
        output.extend_from_slice(&buffer[..read]);
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;

    #[cfg(unix)]
    #[tokio::test]
    async fn command_failure_never_reflects_provider_output() {
        use std::os::unix::fs::PermissionsExt as _;

        let directory = tempfile::tempdir().unwrap();
        let script = directory.path().join("fake-adb");
        std::fs::write(
            &script,
            "#!/bin/sh\nprintf 'hunter2' >&2\nprintf 'partial-secret' >&1\nexit 1\n",
        )
        .unwrap();
        std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o700)).unwrap();
        let error = dump(&script, "emulator-5554").await.unwrap_err();
        assert!(!error.message.contains("hunter2"));
        assert!(!error.message.contains("partial-secret"));
        assert!(error.message.contains("failed with status"));
    }
}
