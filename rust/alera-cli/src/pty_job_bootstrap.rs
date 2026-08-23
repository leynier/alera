use std::ffi::OsStr;
use std::os::windows::ffi::OsStrExt;
use std::process::Command;

use serde::Deserialize;
use windows::core::{BOOL, PCWSTR};
use windows::Win32::Foundation::{CloseHandle, WAIT_OBJECT_0};
use windows::Win32::System::Console::{SetConsoleCtrlHandler, CTRL_BREAK_EVENT, CTRL_C_EVENT};
use windows::Win32::System::Threading::{
    OpenEventW, OpenProcess, WaitForMultipleObjects, PROCESS_SYNCHRONIZE,
    SYNCHRONIZATION_SYNCHRONIZE,
};

pub(crate) const BOOTSTRAP_ARGUMENT: &str = "__pty-job-bootstrap";
pub(crate) const BOOTSTRAP_EVENT_ENV: &str = "ALERA_PTY_JOB_BOOTSTRAP_EVENT";
pub(crate) const BOOTSTRAP_PARENT_PID_ENV: &str = "ALERA_PTY_JOB_BOOTSTRAP_PARENT_PID";
pub(crate) const BOOTSTRAP_REQUEST_ENV: &str = "ALERA_PTY_JOB_BOOTSTRAP_REQUEST";

#[derive(Deserialize)]
struct BootstrapRequest {
    shell: String,
    arguments: Vec<String>,
}

pub(crate) fn is_invocation() -> bool {
    std::env::args_os().nth(1).as_deref() == Some(OsStr::new(BOOTSTRAP_ARGUMENT))
}

pub(crate) fn run() -> i32 {
    match run_inner() {
        Ok(code) => code,
        Err(error) => {
            tracing::error!("PTY Job bootstrap failed: {error}");
            1
        }
    }
}

fn run_inner() -> Result<i32, String> {
    let request = std::env::var(BOOTSTRAP_REQUEST_ENV)
        .map_err(|error| format!("missing launch request: {error}"))?;
    let request: BootstrapRequest = serde_json::from_str(&request)
        .map_err(|error| format!("invalid launch request: {error}"))?;
    install_control_handler()?;
    wait_for_release()?;

    // This process is already attached to ConPTY and its Job Object. The shell
    // must inherit both, so CREATE_NO_WINDOW from the normal command boundary
    // is intentionally not applicable here.
    #[allow(clippy::disallowed_methods)]
    let status = Command::new(&request.shell)
        .args(&request.arguments)
        .env_remove(BOOTSTRAP_EVENT_ENV)
        .env_remove(BOOTSTRAP_PARENT_PID_ENV)
        .env_remove(BOOTSTRAP_REQUEST_ENV)
        .spawn()
        .map_err(|error| format!("failed to launch {}: {error}", request.shell))?
        .wait()
        .map_err(|error| format!("failed to wait for {}: {error}", request.shell))?;
    Ok(status.code().unwrap_or(1))
}

fn install_control_handler() -> Result<(), String> {
    // A null handler toggles an inheritable ignore-Ctrl+C attribute. Clear it
    // first, then install a process-local handler so the real shell inherits
    // normal Ctrl+C behavior while this waiting bootstrap remains alive.
    unsafe { SetConsoleCtrlHandler(None, false) }
        .map_err(|error| format!("failed to reset console control handling: {error}"))?;
    unsafe { SetConsoleCtrlHandler(Some(handle_console_control), true) }
        .map_err(|error| format!("failed to protect PTY Job bootstrap: {error}"))
}

unsafe extern "system" fn handle_console_control(control: u32) -> BOOL {
    BOOL::from(matches!(control, CTRL_C_EVENT | CTRL_BREAK_EVENT))
}

pub(crate) fn wait_for_release() -> Result<(), String> {
    let event_name = std::env::var(BOOTSTRAP_EVENT_ENV)
        .map_err(|error| format!("missing release event: {error}"))?;
    let parent_pid = std::env::var(BOOTSTRAP_PARENT_PID_ENV)
        .map_err(|error| format!("missing parent pid: {error}"))?
        .parse::<u32>()
        .map_err(|error| format!("invalid parent pid: {error}"))?;
    let mut event_name: Vec<u16> = OsStr::new(&event_name).encode_wide().collect();
    event_name.push(0);

    let event = unsafe {
        OpenEventW(
            SYNCHRONIZATION_SYNCHRONIZE,
            false,
            PCWSTR(event_name.as_ptr()),
        )
    }
    .map_err(|error| format!("failed to open release event: {error}"))?;
    let parent = unsafe { OpenProcess(PROCESS_SYNCHRONIZE, false, parent_pid) }
        .map_err(|error| format!("failed to open parent process: {error}"))?;
    let result = unsafe { WaitForMultipleObjects(&[event, parent], false, u32::MAX) };
    let _ = unsafe { CloseHandle(parent) };
    let _ = unsafe { CloseHandle(event) };

    if result == WAIT_OBJECT_0 {
        Ok(())
    } else if result.0 == WAIT_OBJECT_0.0 + 1 {
        Err("terminal host exited before Job Object association".to_string())
    } else {
        Err(format!(
            "failed waiting for Job Object association: {result:?}"
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Helper process for the Job Object integration test. A normal test run
    /// returns without spawning anything; the parent test opts in explicitly.
    #[test]
    #[allow(clippy::zombie_processes)]
    fn job_tree_child() {
        let Some(mode) = std::env::var_os("ALERA_PTY_JOB_TEST_CHILD") else {
            return;
        };
        wait_for_release().expect("release");
        #[allow(clippy::disallowed_methods)]
        let mut descendant = Command::new("ping")
            .args(["-t", "127.0.0.1"])
            .spawn()
            .expect("ping");
        std::fs::write(
            std::env::var("ALERA_PTY_JOB_TEST_PID_FILE").expect("pid file"),
            descendant.id().to_string(),
        )
        .expect("write descendant pid");
        if mode == "wait" {
            let _ = descendant.wait();
        }
    }
}
