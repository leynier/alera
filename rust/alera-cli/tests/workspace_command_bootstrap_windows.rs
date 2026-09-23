//! Native command bootstrap coverage without a PTY or a user runtime.
#![cfg(windows)]

use std::ffi::{c_void, OsStr};
use std::io::Write;
use std::mem::size_of;
use std::os::windows::ffi::OsStrExt;
use std::os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle};
use std::process::{Child, Stdio};
use std::time::{Duration, Instant};

use alera_core::child_process::windowless_command;
use windows::core::PCWSTR;
use windows::Win32::Foundation::HANDLE;
use windows::Win32::System::JobObjects::{
    AssignProcessToJobObject, CreateJobObjectW, JobObjectExtendedLimitInformation,
    SetInformationJobObject, JOBOBJECT_EXTENDED_LIMIT_INFORMATION,
    JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
};
use windows::Win32::System::Threading::{CreateEventW, SetEvent};

struct OwnedChild(Child);
impl Drop for OwnedChild {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

#[test]
fn native_command_bootstrap_waits_for_assignment_and_preserves_stdio() {
    let directory = tempfile::tempdir().unwrap();
    let event_name = format!("Local\\alera-command-test-{}", uuid::Uuid::new_v4());
    let wide: Vec<u16> = OsStr::new(&event_name)
        .encode_wide()
        .chain(Some(0))
        .collect();
    let event = unsafe {
        OwnedHandle::from_raw_handle(
            CreateEventW(None, true, false, PCWSTR(wide.as_ptr()))
                .unwrap()
                .0,
        )
    };
    let job =
        unsafe { OwnedHandle::from_raw_handle(CreateJobObjectW(None, PCWSTR::null()).unwrap().0) };
    let mut limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION::default();
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    unsafe {
        SetInformationJobObject(
            HANDLE(job.as_raw_handle()),
            JobObjectExtendedLimitInformation,
            (&limits as *const JOBOBJECT_EXTENDED_LIMIT_INFORMATION).cast::<c_void>(),
            size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
        )
        .unwrap();
    }
    let script = directory.path().join("agent.cmd");
    std::fs::write(
        &script,
        "@echo off\r\nset /p task_input=\r\necho %task_input%\r\n>started.txt echo started\r\n",
    )
    .unwrap();
    let mut child = OwnedChild(
        windowless_command(env!("CARGO_BIN_EXE_alera"))
            .arg("__workspace-job-bootstrap")
            .current_dir(directory.path())
            .env("ALERA_PTY_JOB_BOOTSTRAP_EVENT", &event_name)
            .env(
                "ALERA_PTY_JOB_BOOTSTRAP_PARENT_PID",
                std::process::id().to_string(),
            )
            .env(
                "ALERA_PTY_JOB_BOOTSTRAP_REQUEST",
                serde_json::json!({
                    "shell": "cmd.exe", "arguments": ["/d", "/c", "agent.cmd"],
                })
                .to_string(),
            )
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap(),
    );
    child
        .0
        .stdin
        .take()
        .unwrap()
        .write_all(b"fixture payload\r\n")
        .unwrap();
    std::thread::sleep(Duration::from_millis(100));
    assert!(child.0.try_wait().unwrap().is_none());
    assert!(!directory.path().join("started.txt").exists());
    unsafe {
        AssignProcessToJobObject(HANDLE(job.as_raw_handle()), HANDLE(child.0.as_raw_handle()))
            .unwrap();
        SetEvent(HANDLE(event.as_raw_handle())).unwrap();
    }
    let deadline = Instant::now() + Duration::from_secs(15);
    let status = loop {
        if let Some(status) = child.0.try_wait().unwrap() {
            break status;
        }
        assert!(Instant::now() < deadline, "native bootstrap did not finish");
        std::thread::sleep(Duration::from_millis(20));
    };
    drop(job);
    use std::io::Read;
    let mut stdout = String::new();
    let mut stderr = String::new();
    child
        .0
        .stdout
        .take()
        .unwrap()
        .read_to_string(&mut stdout)
        .unwrap();
    child
        .0
        .stderr
        .take()
        .unwrap()
        .read_to_string(&mut stderr)
        .unwrap();
    assert!(status.success(), "{status}: {stderr}");
    assert_eq!(stdout.trim(), "fixture payload");
    assert!(directory.path().join("started.txt").exists());
}
