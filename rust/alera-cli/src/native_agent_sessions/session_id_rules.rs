use crate::terminal_host::orchestration::agent_session_resume::usable_native_session_id;

use super::{CleanupFailure, NativeAgentSessionRef, RegisteredSession};

/// Whether `name` can only ever address one entry directly inside a storage
/// directory: no separators, no `..`, nothing a filesystem would reinterpret.
pub(super) fn is_storage_entry_name(name: &str) -> bool {
    !name.is_empty()
        && name != "."
        && !name.contains("..")
        && !name
            .chars()
            .any(|ch| matches!(ch, '/' | '\\' | ':' | '\0') || ch.is_control())
}

/// An id that is safe both as a CLI argument and as a path component.
pub(super) fn command_session_id(id: &str) -> Result<&str, CleanupFailure> {
    usable_native_session_id(id)
        .filter(|id| is_storage_entry_name(id))
        .ok_or_else(|| CleanupFailure::new("unusable_session_id", "unusable session id"))
}

pub(super) fn registered_session(
    session: &NativeAgentSessionRef,
) -> Result<RegisteredSession, CleanupFailure> {
    let id = command_session_id(&session.session_id)?.to_string();
    let ccs_profile = match session.ccs_profile.as_deref().map(str::trim) {
        None | Some("") => None,
        Some(profile) if is_storage_entry_name(profile) && !profile.starts_with('-') => {
            Some(profile.to_string())
        }
        Some(_) => {
            return Err(CleanupFailure::new(
                "unusable_ccs_profile",
                "unusable CCS profile name",
            ))
        }
    };
    Ok(RegisteredSession { id, ccs_profile })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn storage_entry_names_cannot_leave_their_directory() {
        for name in ["", ".", "..", "a/b", "a\\b", "../x", "a..b", "c:", "a\0b"] {
            assert!(!is_storage_entry_name(name), "{name:?}");
        }
        for name in ["ses_abc", "0198-uuid", "T-1234", "-bj25iWTDGOE"] {
            assert!(is_storage_entry_name(name), "{name:?}");
        }
    }

    #[test]
    fn command_ids_reject_shell_metacharacters_and_flags() {
        for id in ["--all", "a;b", "$(x)", "a b", "../etc", "a/b"] {
            assert!(command_session_id(id).is_err(), "{id:?}");
        }
        assert_eq!(command_session_id(" abc ").unwrap(), "abc");
    }
}
