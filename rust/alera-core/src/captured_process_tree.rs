use tokio::process::{Child, Command};

#[cfg(unix)]
use std::sync::atomic::{AtomicI32, Ordering};

/// Keeps enough platform state to terminate an invocation after its direct
/// child has already been reaped.
pub struct ProcessTreeGuard {
    #[cfg(unix)]
    process_group_id: AtomicI32,
    #[cfg(windows)]
    job: WindowsProcessJob,
}

impl ProcessTreeGuard {
    pub fn prepare_command(command: &mut Command) {
        // Tokio's reaper keeps a dropped child collectible after this guard
        // kills its process tree. Callers should not have to remember this
        // safety option when they build a command for the shared collector.
        command.kill_on_drop(true);
        #[cfg(unix)]
        command.process_group(0);
        #[cfg(windows)]
        command.creation_flags(CREATE_NO_WINDOW | CREATE_SUSPENDED);
        #[cfg(not(any(unix, windows)))]
        let _ = command;
    }

    pub fn attach(child: &Child) -> Result<Self, String> {
        #[cfg(unix)]
        {
            Ok(Self {
                process_group_id: AtomicI32::new(
                    child.id().map(|pid| pid as i32).unwrap_or_default(),
                ),
            })
        }
        #[cfg(windows)]
        {
            Ok(Self {
                job: WindowsProcessJob::attach(child)?,
            })
        }
        #[cfg(not(any(unix, windows)))]
        {
            let _ = child;
            Ok(Self {})
        }
    }

    pub fn terminate(&self) {
        #[cfg(unix)]
        {
            let process_group_id = self.process_group_id.swap(0, Ordering::AcqRel);
            if process_group_id > 0 {
                // Safe: a process group that already exited simply returns ESRCH.
                unsafe {
                    libc::kill(-process_group_id, libc::SIGKILL);
                }
            }
        }
        #[cfg(windows)]
        self.job.terminate();
    }
}

impl Drop for ProcessTreeGuard {
    fn drop(&mut self) {
        self.terminate();
    }
}

#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x0800_0000;
#[cfg(windows)]
const CREATE_SUSPENDED: u32 = 0x0000_0004;

#[cfg(windows)]
struct WindowsProcessJob {
    handle: std::os::windows::io::OwnedHandle,
    terminated: std::sync::atomic::AtomicBool,
}

#[cfg(windows)]
impl WindowsProcessJob {
    fn attach(child: &Child) -> Result<Self, String> {
        use std::ffi::c_void;
        use std::mem::size_of;
        use std::os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle};
        use windows::core::PCWSTR;
        use windows::Win32::Foundation::HANDLE;
        use windows::Win32::System::JobObjects::{
            AssignProcessToJobObject, CreateJobObjectW, JobObjectExtendedLimitInformation,
            SetInformationJobObject, JOBOBJECT_EXTENDED_LIMIT_INFORMATION,
            JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
        };

        let raw = unsafe { CreateJobObjectW(None, PCWSTR::null()) }
            .map_err(|error| format!("failed to create process job: {error}"))?;
        let handle = unsafe { OwnedHandle::from_raw_handle(raw.0) };
        let mut limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION::default();
        limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        unsafe {
            SetInformationJobObject(
                HANDLE(handle.as_raw_handle()),
                JobObjectExtendedLimitInformation,
                (&limits as *const JOBOBJECT_EXTENDED_LIMIT_INFORMATION).cast::<c_void>(),
                size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
            )
        }
        .map_err(|error| format!("failed to configure process job: {error}"))?;
        let process = child
            .raw_handle()
            .ok_or_else(|| "process did not expose a Windows handle".to_string())?;
        unsafe { AssignProcessToJobObject(HANDLE(handle.as_raw_handle()), HANDLE(process)) }
            .map_err(|error| format!("failed to assign process job: {error}"))?;
        // Tokio exposes the process handle but not CreateProcess's primary
        // thread handle. The command is suspended before spawn; enumerate that
        // one thread only after the job owns the process, then resume it.
        resume_suspended_process(
            child
                .id()
                .ok_or_else(|| "process exited before job assignment".to_string())?,
        )?;
        Ok(Self {
            handle,
            terminated: std::sync::atomic::AtomicBool::new(false),
        })
    }

    fn terminate(&self) {
        use std::os::windows::io::AsRawHandle;
        use windows::Win32::Foundation::HANDLE;
        use windows::Win32::System::JobObjects::TerminateJobObject;

        if !self
            .terminated
            .swap(true, std::sync::atomic::Ordering::AcqRel)
        {
            let _ = unsafe { TerminateJobObject(HANDLE(self.handle.as_raw_handle()), 1) };
        }
    }
}

#[cfg(windows)]
fn resume_suspended_process(process_id: u32) -> Result<(), String> {
    use std::os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle};
    use windows::Win32::Foundation::HANDLE;
    use windows::Win32::System::Diagnostics::ToolHelp::{
        CreateToolhelp32Snapshot, Thread32First, Thread32Next, TH32CS_SNAPTHREAD, THREADENTRY32,
    };
    use windows::Win32::System::Threading::{OpenThread, ResumeThread, THREAD_SUSPEND_RESUME};

    let snapshot = unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0) }
        .map_err(|error| format!("failed to enumerate process threads: {error}"))?;
    let snapshot = unsafe { OwnedHandle::from_raw_handle(snapshot.0) };
    let mut entry = THREADENTRY32 {
        dwSize: std::mem::size_of::<THREADENTRY32>() as u32,
        ..Default::default()
    };
    let first = unsafe { Thread32First(HANDLE(snapshot.as_raw_handle()), &mut entry) };
    if first.is_err() {
        return Err("could not find the suspended process thread".to_string());
    }
    loop {
        if entry.th32OwnerProcessID == process_id {
            let thread = unsafe { OpenThread(THREAD_SUSPEND_RESUME, false, entry.th32ThreadID) }
                .map_err(|error| format!("failed to open suspended process thread: {error}"))?;
            let thread = unsafe { OwnedHandle::from_raw_handle(thread.0) };
            let previous_count = unsafe { ResumeThread(HANDLE(thread.as_raw_handle())) };
            if previous_count == u32::MAX {
                return Err(format!(
                    "failed to resume suspended process: {}",
                    std::io::Error::last_os_error()
                ));
            }
            return Ok(());
        }
        if unsafe { Thread32Next(HANDLE(snapshot.as_raw_handle()), &mut entry) }.is_err() {
            break;
        }
    }
    Err("could not find the suspended process thread".to_string())
}
