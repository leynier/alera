use std::ffi::c_void;
use std::mem::size_of;
use std::os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle};

use windows::core::{BOOL, HRESULT};
use windows::Win32::Foundation::{
    ERROR_INVALID_PARAMETER, ERROR_MORE_DATA, HANDLE, WAIT_OBJECT_0, WAIT_TIMEOUT,
};
use windows::Win32::System::JobObjects::{
    IsProcessInJob, JobObjectBasicAccountingInformation, JobObjectBasicProcessIdList,
    QueryInformationJobObject, TerminateJobObject, JOBOBJECT_BASIC_ACCOUNTING_INFORMATION,
    JOBOBJECT_BASIC_PROCESS_ID_LIST,
};
use windows::Win32::System::Threading::{
    OpenProcess, WaitForSingleObject, PROCESS_QUERY_LIMITED_INFORMATION, PROCESS_SYNCHRONIZE,
};

use crate::terminal_host::host_error::HostResult;

use super::{shutdown_error, Session, GRACE_PERIOD, KILL_PERIOD, POLL_INTERVAL};

#[derive(Default)]
pub(super) struct ShutdownGuard {
    jobs: Vec<OwnedHandle>,
    processes: Vec<OwnedHandle>,
}

impl ShutdownGuard {
    pub(super) async fn capture(sessions: &[&Session]) -> HostResult<Self> {
        let jobs = sessions
            .iter()
            .filter_map(|session| session.process_job.as_ref())
            .map(|job| job.shutdown_handle())
            .collect::<HostResult<Vec<_>>>()?;
        let mut processes = Vec::new();
        for job in &jobs {
            processes.extend(capture_processes(job)?);
        }
        Ok(Self { jobs, processes })
    }

    pub(super) async fn wait(&mut self) -> HostResult<()> {
        // A retained handle keeps KILL_ON_JOB_CLOSE from firing. Terminate
        // explicitly, then keep ownership until every member has actually left.
        for job in &self.jobs {
            self.processes.extend(capture_processes(job)?);
            unsafe { TerminateJobObject(HANDLE(job.as_raw_handle()), 1) }
                .map_err(shutdown_error)?;
        }
        let deadline = tokio::time::Instant::now() + GRACE_PERIOD + KILL_PERIOD;
        loop {
            let mut running = false;
            for job in &self.jobs {
                let mut info = JOBOBJECT_BASIC_ACCOUNTING_INFORMATION::default();
                // Safe: the owned handle remains valid, and info has the size
                // and layout required by the selected accounting class.
                unsafe {
                    QueryInformationJobObject(
                        Some(HANDLE(job.as_raw_handle())),
                        JobObjectBasicAccountingInformation,
                        (&mut info as *mut JOBOBJECT_BASIC_ACCOUNTING_INFORMATION).cast::<c_void>(),
                        size_of::<JOBOBJECT_BASIC_ACCOUNTING_INFORMATION>() as u32,
                        None,
                    )
                }
                .map_err(shutdown_error)?;
                running |= info.ActiveProcesses != 0;
            }
            // Job accounting can reach zero before process objects become
            // signalled. Their native handles are the final teardown boundary.
            for process in &self.processes {
                match unsafe { WaitForSingleObject(HANDLE(process.as_raw_handle()), 0) } {
                    WAIT_OBJECT_0 => {}
                    WAIT_TIMEOUT => running = true,
                    _ => return Err(shutdown_error("failed to wait for a terminal process")),
                }
            }
            if !running {
                self.processes.clear();
                self.jobs.clear();
                return Ok(());
            }
            if tokio::time::Instant::now() >= deadline {
                return Err(shutdown_error(
                    "terminal jobs did not exit before the deadline",
                ));
            }
            tokio::time::sleep(POLL_INTERVAL).await;
        }
    }
}

fn capture_processes(job: &OwnedHandle) -> HostResult<Vec<OwnedHandle>> {
    let job = HANDLE(job.as_raw_handle());
    let mut capacity = 64;
    let mut processes = Vec::new();
    loop {
        // usize storage aligns the variable-length ProcessIdList on both
        // Windows architectures. The first two DWORDs form its header.
        let header_words = 8_usize.div_ceil(size_of::<usize>());
        let mut buffer = vec![0_usize; header_words + capacity];
        let result = unsafe {
            QueryInformationJobObject(
                Some(job),
                JobObjectBasicProcessIdList,
                buffer.as_mut_ptr().cast::<c_void>(),
                (buffer.len() * size_of::<usize>()) as u32,
                None,
            )
        };
        if let Err(error) = result {
            if error.code() == HRESULT::from_win32(ERROR_MORE_DATA.0) && capacity < 65_536 {
                capacity *= 2;
                continue;
            }
            return Err(shutdown_error(error));
        }
        let list = unsafe { &*buffer.as_ptr().cast::<JOBOBJECT_BASIC_PROCESS_ID_LIST>() };
        let count = list.NumberOfProcessIdsInList as usize;
        if count > capacity {
            return Err(shutdown_error("invalid terminal job process list"));
        }
        for pid in &buffer[header_words..header_words + count] {
            let raw = match unsafe {
                OpenProcess(
                    PROCESS_SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION,
                    false,
                    *pid as u32,
                )
            } {
                Ok(handle) => handle,
                Err(error) if error.code() == HRESULT::from_win32(ERROR_INVALID_PARAMETER.0) => {
                    continue
                }
                Err(error) => return Err(shutdown_error(error)),
            };
            // Transfer each handle once and recheck membership after opening:
            // an exited job member's pid may already have been recycled.
            let handle = unsafe { OwnedHandle::from_raw_handle(raw.0) };
            let mut belongs = BOOL::default();
            unsafe { IsProcessInJob(raw, Some(job), &mut belongs) }.map_err(shutdown_error)?;
            if belongs.as_bool() {
                processes.push(handle);
            }
        }
        return Ok(processes);
    }
}
