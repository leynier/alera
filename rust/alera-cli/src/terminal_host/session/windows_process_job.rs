use std::ffi::{c_void, OsStr};
use std::mem::size_of;
use std::os::windows::ffi::OsStrExt;
use std::os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle};

use portable_pty::{Child, CommandBuilder};
use windows::core::PCWSTR;
use windows::Win32::Foundation::{HANDLE, WAIT_FAILED, WAIT_OBJECT_0};
use windows::Win32::System::JobObjects::{
    AssignProcessToJobObject, CreateJobObjectW, JobObjectExtendedLimitInformation,
    SetInformationJobObject, JOBOBJECT_EXTENDED_LIMIT_INFORMATION,
    JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
};
use windows::Win32::System::Threading::{
    CreateEventW, SetEvent, TerminateProcess, WaitForSingleObject,
};

use crate::pty_job_bootstrap::{
    BOOTSTRAP_ARGUMENT, BOOTSTRAP_EVENT_ENV, BOOTSTRAP_PARENT_PID_ENV, BOOTSTRAP_REQUEST_ENV,
};
use crate::terminal_host::host_error::{HostError, HostResult};
use crate::terminal_host::protocol::TerminalHostLaunch;

/// Owns the Windows Job Object that contains one PTY shell and all processes it
/// subsequently creates. Dropping the last handle terminates every process
/// still in the job.
pub(crate) struct WindowsProcessJob {
    handle: OwnedHandle,
    release_event: OwnedHandle,
    release_event_name: String,
}

impl WindowsProcessJob {
    pub(crate) fn shutdown_handle(&self) -> HostResult<OwnedHandle> {
        self.handle.try_clone().map_err(|error| {
            HostError::state(format!(
                "failed to retain PTY process job for shutdown: {error}"
            ))
        })
    }

    pub(crate) fn create() -> HostResult<Self> {
        // Safe: both arguments are null, so Windows creates an unnamed job with
        // default security attributes and returns an owned handle.
        let raw = unsafe { CreateJobObjectW(None, PCWSTR::null()) }.map_err(|error| {
            HostError::state(format!("failed to create PTY process job: {error}"))
        })?;
        // Safe: CreateJobObjectW returned a fresh handle whose ownership is
        // transferred exactly once to OwnedHandle.
        let handle = unsafe { OwnedHandle::from_raw_handle(raw.0) };
        let mut limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION::default();
        limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        // Safe: `limits` has the exact layout and size required by the selected
        // information class and remains alive for the duration of the call.
        unsafe {
            SetInformationJobObject(
                Self::raw_handle(&handle),
                JobObjectExtendedLimitInformation,
                (&limits as *const JOBOBJECT_EXTENDED_LIMIT_INFORMATION).cast::<c_void>(),
                size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
            )
        }
        .map_err(|error| {
            HostError::state(format!("failed to configure PTY process job: {error}"))
        })?;
        let event_name = format!("Local\\alera-pty-job-{}", uuid::Uuid::new_v4());
        let mut wide_name: Vec<u16> = OsStr::new(&event_name).encode_wide().collect();
        wide_name.push(0);
        let raw_event = unsafe { CreateEventW(None, true, false, PCWSTR(wide_name.as_ptr())) }
            .map_err(|error| {
                HostError::state(format!("failed to create PTY Job release event: {error}"))
            })?;
        let release_event = unsafe { OwnedHandle::from_raw_handle(raw_event.0) };
        Ok(Self {
            handle,
            release_event,
            release_event_name: event_name,
        })
    }

    pub(super) fn bootstrap_command(
        &self,
        launch: &TerminalHostLaunch,
    ) -> HostResult<CommandBuilder> {
        let executable = std::env::current_exe().map_err(|error| {
            HostError::state(format!("failed to locate PTY Job bootstrap: {error}"))
        })?;
        let request = serde_json::to_string(&serde_json::json!({
            "shell": launch.shell,
            "arguments": launch.arguments,
        }))
        .map_err(|error| HostError::state(format!("failed to encode PTY launch: {error}")))?;
        let mut command = CommandBuilder::new(executable);
        command.arg(BOOTSTRAP_ARGUMENT);
        command.env_clear();
        for (key, value) in &launch.environment {
            command.env(key, value);
        }
        command.env(BOOTSTRAP_EVENT_ENV, &self.release_event_name);
        command.env(BOOTSTRAP_PARENT_PID_ENV, std::process::id().to_string());
        command.env(BOOTSTRAP_REQUEST_ENV, request);
        Ok(command)
    }

    pub(crate) fn command_bootstrap(
        &self,
        binary: &str,
        arguments: &[String],
    ) -> HostResult<tokio::process::Command> {
        let executable =
            std::env::current_exe().map_err(|error| HostError::state(error.to_string()))?;
        let mut command = alera_core::child_process::windowless_async_command(executable);
        command.arg(crate::pty_job_bootstrap::COMMAND_BOOTSTRAP_ARGUMENT);
        command.env(BOOTSTRAP_EVENT_ENV, &self.release_event_name);
        command.env(BOOTSTRAP_PARENT_PID_ENV, std::process::id().to_string());
        command.env(
            BOOTSTRAP_REQUEST_ENV,
            serde_json::to_string(&serde_json::json!({
                "shell": binary, "arguments": arguments,
            }))
            .map_err(|error| HostError::state(error.to_string()))?,
        );
        Ok(command)
    }

    pub(crate) fn assign_command_and_release(
        &self,
        child: &tokio::process::Child,
    ) -> HostResult<()> {
        let handle = child.raw_handle().ok_or_else(|| {
            HostError::state("Command bootstrap did not expose its process handle")
        })?;
        self.assign_handle_and_release(HANDLE(handle))
    }

    pub(super) fn assign_and_release(&self, child: &dyn Child) -> HostResult<()> {
        let process = child.as_raw_handle().ok_or_else(|| {
            HostError::state("PTY Job bootstrap did not expose its process handle")
        })?;
        self.assign_handle_and_release(HANDLE(process))
    }

    fn assign_handle_and_release(&self, process: HANDLE) -> HostResult<()> {
        // Safe: both handles are valid for this call. The job remains owned by
        // the session and the child owns `process` throughout the call.
        self.assign_process(process)?;
        if let Err(error) = unsafe { SetEvent(Self::raw_handle(&self.release_event)) } {
            let cleanup = terminate_and_wait(process)
                .err()
                .map(|cleanup| format!("; cleanup also failed: {cleanup}"))
                .unwrap_or_default();
            return Err(HostError::state(format!(
                "failed to release PTY Job bootstrap: {error}{cleanup}"
            )));
        }
        Ok(())
    }

    fn assign_process(&self, process: HANDLE) -> HostResult<()> {
        assign_process_to_job(Self::raw_handle(&self.handle), process)
    }

    fn raw_handle(handle: &OwnedHandle) -> HANDLE {
        HANDLE(handle.as_raw_handle())
    }
}

fn assign_process_to_job(job: HANDLE, process: HANDLE) -> HostResult<()> {
    unsafe { AssignProcessToJobObject(job, process) }.map_err(|error| {
        let cleanup = terminate_and_wait(process)
            .err()
            .map(|cleanup| format!("; cleanup also failed: {cleanup}"))
            .unwrap_or_default();
        HostError::state(format!(
            "failed to assign PTY bootstrap to process job: {error}{cleanup}"
        ))
    })
}

fn terminate_and_wait(process: HANDLE) -> Result<(), String> {
    unsafe { TerminateProcess(process, 1) }
        .map_err(|error| format!("failed to terminate PTY bootstrap: {error}"))?;
    let result = unsafe { WaitForSingleObject(process, 5_000) };
    if result == WAIT_OBJECT_0 {
        Ok(())
    } else if result == WAIT_FAILED {
        Err("failed to wait for PTY bootstrap termination".to_string())
    } else {
        Err(format!(
            "unexpected PTY bootstrap termination wait result: {result:?}"
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::process::Command;
    use std::time::{Duration, Instant};

    use windows::Win32::System::JobObjects::{QueryInformationJobObject, JOB_OBJECT_LIMIT};
    use windows::Win32::System::Threading::{OpenProcess, PROCESS_SYNCHRONIZE};

    #[test]
    fn job_is_configured_to_kill_processes_when_closed() {
        let job = WindowsProcessJob::create().expect("job");
        let mut limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION::default();

        unsafe {
            QueryInformationJobObject(
                Some(WindowsProcessJob::raw_handle(&job.handle)),
                JobObjectExtendedLimitInformation,
                (&mut limits as *mut JOBOBJECT_EXTENDED_LIMIT_INFORMATION).cast::<c_void>(),
                size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
                None,
            )
        }
        .expect("query job limits");

        assert_ne!(
            limits.BasicLimitInformation.LimitFlags & JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
            JOB_OBJECT_LIMIT(0)
        );
    }

    #[allow(clippy::disallowed_methods)]
    fn spawn_gated_root(
        job: &WindowsProcessJob,
        mode: &str,
        pid_file: &std::path::Path,
    ) -> std::process::Child {
        Command::new(std::env::current_exe().expect("test executable"))
            .args([
                "--exact",
                "pty_job_bootstrap::tests::job_tree_child",
                "--nocapture",
            ])
            .env("ALERA_PTY_JOB_TEST_CHILD", mode)
            .env("ALERA_PTY_JOB_TEST_PID_FILE", pid_file)
            .env(BOOTSTRAP_EVENT_ENV, &job.release_event_name)
            .env(BOOTSTRAP_PARENT_PID_ENV, std::process::id().to_string())
            .spawn()
            .expect("spawn gated root")
    }

    fn wait_for_descendant(pid_file: &std::path::Path) -> HANDLE {
        let deadline = Instant::now() + Duration::from_secs(5);
        while !pid_file.exists() && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(25));
        }
        let descendant_pid = std::fs::read_to_string(pid_file)
            .expect("descendant pid")
            .parse::<u32>()
            .expect("numeric descendant pid");
        unsafe { OpenProcess(PROCESS_SYNCHRONIZE, false, descendant_pid) }.expect("open descendant")
    }

    fn process_handle(child: &std::process::Child) -> HANDLE {
        HANDLE(std::os::windows::io::AsRawHandle::as_raw_handle(child))
    }

    fn release(job: &WindowsProcessJob) {
        unsafe { SetEvent(WindowsProcessJob::raw_handle(&job.release_event)) }
            .expect("release root");
    }

    #[test]
    #[allow(clippy::disallowed_methods)]
    fn closing_the_job_terminates_the_root_and_its_early_descendant() {
        let job = WindowsProcessJob::create().expect("job");
        let temp = tempfile::tempdir().expect("temp dir");
        let pid_file = temp.path().join("descendant.pid");
        let mut root = spawn_gated_root(&job, "wait", &pid_file);
        let root_handle = process_handle(&root);
        job.assign_process(root_handle).expect("assign root");
        release(&job);
        let descendant = wait_for_descendant(&pid_file);

        drop(job);

        assert_eq!(
            unsafe { WaitForSingleObject(root_handle, 5_000) },
            WAIT_OBJECT_0
        );
        assert_eq!(
            unsafe { WaitForSingleObject(descendant, 5_000) },
            WAIT_OBJECT_0
        );
        let _ = unsafe { windows::Win32::Foundation::CloseHandle(descendant) };
        let _ = root.wait();
    }

    #[tokio::test]
    async fn workspace_shutdown_waits_for_the_retained_job_and_its_descendant() {
        let job = WindowsProcessJob::create().expect("job");
        let temp = tempfile::tempdir().expect("temp dir");
        let pid_file = temp.path().join("descendant.pid");
        let mut root = spawn_gated_root(&job, "wait", &pid_file);
        let root_handle = process_handle(&root);
        job.assign_process(root_handle).expect("assign root");
        release(&job);
        let descendant = wait_for_descendant(&pid_file);
        let mut session = super::super::Session::driver_test_stub("test", 80, 24);
        session.process_job = Some(job);
        let mut shutdown =
            super::super::workspace_shutdown::WorkspaceShutdown::capture(std::iter::once(&session))
                .await
                .expect("retain job");
        session.process_job.take();

        shutdown.fail_next_waits(1);
        assert!(shutdown.wait().await.is_err());
        assert_eq!(
            unsafe { WaitForSingleObject(root_handle, 0) },
            windows::Win32::Foundation::WAIT_TIMEOUT
        );
        let mut retry = super::super::workspace_shutdown::WorkspaceShutdown::default();
        retry.merge(shutdown);
        retry.wait().await.expect("workspace shutdown retry");

        assert_eq!(
            unsafe { WaitForSingleObject(root_handle, 0) },
            WAIT_OBJECT_0
        );
        assert_eq!(unsafe { WaitForSingleObject(descendant, 0) }, WAIT_OBJECT_0);
        let _ = unsafe { windows::Win32::Foundation::CloseHandle(descendant) };
        let _ = root.wait();
    }

    #[test]
    #[allow(clippy::disallowed_methods)]
    fn closing_after_natural_root_exit_terminates_the_live_descendant() {
        let job = WindowsProcessJob::create().expect("job");
        let temp = tempfile::tempdir().expect("temp dir");
        let pid_file = temp.path().join("descendant.pid");
        let mut root = spawn_gated_root(&job, "exit", &pid_file);
        let root_handle = process_handle(&root);
        job.assign_process(root_handle).expect("assign root");
        release(&job);
        let descendant = wait_for_descendant(&pid_file);
        assert!(root.wait().expect("wait root").success());

        drop(job);

        assert_eq!(
            unsafe { WaitForSingleObject(descendant, 5_000) },
            WAIT_OBJECT_0
        );
        let _ = unsafe { windows::Win32::Foundation::CloseHandle(descendant) };
    }

    #[test]
    #[allow(clippy::disallowed_methods)]
    fn association_failure_terminates_and_waits_without_releasing_the_root() {
        let job = WindowsProcessJob::create().expect("job");
        let temp = tempfile::tempdir().expect("temp dir");
        let pid_file = temp.path().join("descendant.pid");
        let mut root = spawn_gated_root(&job, "wait", &pid_file);
        let root_handle = process_handle(&root);

        assert!(assign_process_to_job(HANDLE::default(), root_handle).is_err());
        assert_eq!(
            unsafe { WaitForSingleObject(root_handle, 0) },
            WAIT_OBJECT_0
        );
        assert!(!pid_file.exists(), "the gated root spawned a descendant");
        let _ = root.wait();
    }
    #[test]
    fn command_bootstrap_preserves_arguments_in_its_request() {
        let job = WindowsProcessJob::create().unwrap();
        let arguments = vec!["two words".into(), "literal quoted argument".into()];
        let command = job.command_bootstrap("agent.exe", &arguments).unwrap();
        let command = command.as_std();
        assert_eq!(
            command.get_args().collect::<Vec<_>>(),
            vec![OsStr::new(
                crate::pty_job_bootstrap::COMMAND_BOOTSTRAP_ARGUMENT
            )]
        );
        let request = command
            .get_envs()
            .find(|(key, _)| *key == OsStr::new(BOOTSTRAP_REQUEST_ENV))
            .unwrap()
            .1
            .unwrap()
            .to_str()
            .unwrap();
        let request: serde_json::Value = serde_json::from_str(request).unwrap();
        assert_eq!(request["shell"], "agent.exe");
        assert_eq!(request["arguments"], serde_json::json!(arguments));
    }

    #[tokio::test]
    async fn command_job_gates_start_and_verifies_descendant_shutdown() {
        let job = WindowsProcessJob::create().unwrap();
        let temp = tempfile::tempdir().unwrap();
        let pid_file = temp.path().join("command-child.pid");
        let mut command =
            alera_core::child_process::windowless_async_command(std::env::current_exe().unwrap());
        command
            .args([
                "--exact",
                "pty_job_bootstrap::tests::job_tree_child",
                "--nocapture",
            ])
            .env("ALERA_PTY_JOB_TEST_CHILD", "wait")
            .env("ALERA_PTY_JOB_TEST_PID_FILE", &pid_file)
            .env(BOOTSTRAP_EVENT_ENV, &job.release_event_name)
            .env(BOOTSTRAP_PARENT_PID_ENV, std::process::id().to_string())
            .kill_on_drop(true);
        let mut root = command.spawn().unwrap();
        tokio::time::sleep(Duration::from_millis(100)).await;
        assert!(!pid_file.exists(), "command started before job assignment");
        job.assign_command_and_release(&root).unwrap();
        let descendant = wait_for_descendant(&pid_file);
        let mut shutdown =
            super::super::workspace_shutdown::WorkspaceShutdown::capture_command_job(&job).unwrap();
        drop(job);
        shutdown.wait().await.unwrap();
        assert_eq!(unsafe { WaitForSingleObject(descendant, 0) }, WAIT_OBJECT_0);
        let _ = unsafe { windows::Win32::Foundation::CloseHandle(descendant) };
        assert!(!root.wait().await.unwrap().success());
    }
}
