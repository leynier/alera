use windows::Win32::System::RemoteDesktop::{ProcessIdToSessionId, WTSGetActiveConsoleSessionId};
use windows::Win32::System::Threading::GetCurrentProcessId;

/// Whether this process runs in the session that owns the visible desktop.
///
/// UI Automation connects happily from session 0, then reports an empty desktop:
/// a host started over SSH or as a service sees no windows at all. Comparing the
/// sessions says so outright instead of leaving an agent to conclude the user has
/// no applications open.
pub fn runs_in_interactive_session() -> bool {
    match (current_session_id(), active_console_session_id()) {
        (Some(current), Some(console)) => current == console,
        // Either call failing means the answer is unknown; the reader will still
        // report whatever it can see rather than refusing outright.
        _ => true,
    }
}

/// Why this session cannot drive the desktop, for the capability report.
pub fn interactive_session_hint() -> String {
    let current = current_session_id()
        .map(|id| id.to_string())
        .unwrap_or_else(|| "unknown".to_string());
    let console = active_console_session_id()
        .map(|id| id.to_string())
        .unwrap_or_else(|| "unknown".to_string());
    format!(
        "The runtime host is running in Windows session {current}, but the visible desktop is \
         session {console}. UI Automation cannot see another session's windows. Start the \
         runtime host from your own desktop session rather than over a remote shell or as a \
         service."
    )
}

fn current_session_id() -> Option<u32> {
    let mut session = 0u32;
    // SAFETY: both arguments are valid for the duration of the call, and the
    // out-parameter is a plain u32 we own.
    let ok = unsafe { ProcessIdToSessionId(GetCurrentProcessId(), &mut session) };
    ok.is_ok().then_some(session)
}

fn active_console_session_id() -> Option<u32> {
    // SAFETY: no arguments; returns 0xFFFFFFFF when there is no console session.
    let session = unsafe { WTSGetActiveConsoleSessionId() };
    (session != u32::MAX).then_some(session)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Whatever the machine, the hint has to name both sessions and say what to
    /// do, since the user cannot see the numbers otherwise.
    #[test]
    fn the_hint_names_both_sessions_and_the_fix() {
        let hint = interactive_session_hint();
        assert!(hint.contains("session"));
        assert!(hint.contains("desktop session"));
    }

    /// The probe has to answer rather than panic wherever it runs, including in
    /// CI with no console session at all.
    #[test]
    fn the_probe_answers_without_a_console_session() {
        let _ = runs_in_interactive_session();
    }
}
