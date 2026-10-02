use std::collections::HashMap;
use std::sync::OnceLock;
use std::time::Duration;

use tokio::runtime::{Builder, Runtime};

use super::ProcessRunResult;

pub(super) const DEFAULT_MAX_OUTPUT_BYTES: usize =
    alera_core::captured_process::DEFAULT_MAX_OUTPUT_BYTES;
const MAX_OUTPUT_BYTES: usize = alera_core::captured_process::MAX_OUTPUT_BYTES;

pub(super) fn run(
    executable: String,
    arguments: Vec<String>,
    working_directory: Option<String>,
    environment: Option<HashMap<String, String>>,
) -> Result<ProcessRunResult, String> {
    run_with_limits(
        executable,
        arguments,
        working_directory,
        environment,
        DEFAULT_MAX_OUTPUT_BYTES as i32,
        None,
    )
}

pub(super) fn run_with_limits(
    executable: String,
    arguments: Vec<String>,
    working_directory: Option<String>,
    environment: Option<HashMap<String, String>>,
    max_output_bytes: i32,
    timeout_millis: Option<i32>,
) -> Result<ProcessRunResult, String> {
    let max_output_bytes = usize::try_from(max_output_bytes)
        .ok()
        .filter(|value| (1..=MAX_OUTPUT_BYTES).contains(value))
        .ok_or_else(|| {
            format!("process output limit must be between 1 and {MAX_OUTPUT_BYTES} bytes")
        })?;
    let timeout = timeout_millis
        .map(|value| {
            u64::try_from(value)
                .map(Duration::from_millis)
                .map_err(|_| "process timeout must not be negative".to_string())
        })
        .transpose()?;
    let command = alera_core::shell_command::shell_command(
        &executable,
        &arguments,
        working_directory.as_deref(),
        environment.as_ref(),
        true,
    );
    let result = runtime().block_on(alera_core::captured_process::run_command(
        command,
        &executable,
        None,
        max_output_bytes,
        timeout,
    ))?;
    Ok(ProcessRunResult {
        exit_code: result.exit_code,
        stdout: result.stdout,
        stderr: result.stderr,
    })
}

fn runtime() -> &'static Runtime {
    static RUNTIME: OnceLock<Runtime> = OnceLock::new();
    RUNTIME.get_or_init(|| {
        Builder::new_multi_thread()
            .enable_time()
            .enable_io()
            .thread_name("alera-process-output")
            .build()
            .expect("failed to build process output runtime")
    })
}
