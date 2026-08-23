use std::collections::HashMap;

use super::*;

struct FakeProbe {
    processes: HashMap<u32, ProcessLookup>,
}

impl ProcessIdentityProbe for FakeProbe {
    fn lookup(&self, pid: u32) -> ProcessLookup {
        self.processes
            .get(&pid)
            .cloned()
            .unwrap_or(ProcessLookup::Exited)
    }
}

fn identity(pid: u32, start_marker: u64) -> ProcessIdentity {
    ProcessIdentity { pid, start_marker }
}

fn probe(entries: impl IntoIterator<Item = (u32, ProcessLookup)>) -> FakeProbe {
    FakeProbe {
        processes: entries.into_iter().collect(),
    }
}

#[test]
fn a_live_owner_rejects_a_concurrent_start_without_rewriting_metadata() {
    let dir = tempfile::tempdir().unwrap();
    let owner = identity(100, 1_000);
    let challenger = identity(200, 2_000);
    let probe = probe([(owner.pid, ProcessLookup::Live(owner))]);
    let _guard = RuntimeOwnerGuard::acquire_with_probe(dir.path(), owner, &probe).unwrap();
    let before = std::fs::read(dir.path().join(OWNER_FILE_NAME)).unwrap();

    let error = RuntimeOwnerGuard::acquire_with_probe(dir.path(), challenger, &probe)
        .err()
        .expect("concurrent owner should be rejected");

    assert!(error.to_string().contains("live runtime host process 100"));
    assert_eq!(
        std::fs::read(dir.path().join(OWNER_FILE_NAME)).unwrap(),
        before
    );
}

#[test]
fn stale_owner_is_replaced_only_after_the_process_exited() {
    let dir = tempfile::tempdir().unwrap();
    let old = identity(100, 1_000);
    let replacement = identity(200, 2_000);
    let old_probe = probe([(old.pid, ProcessLookup::Live(old))]);
    let guard = RuntimeOwnerGuard::acquire_with_probe(dir.path(), old, &old_probe).unwrap();
    drop(guard);

    let exited_probe = probe([(old.pid, ProcessLookup::Exited)]);
    let _replacement =
        RuntimeOwnerGuard::acquire_with_probe(dir.path(), replacement, &exited_probe).unwrap();
    assert_eq!(
        read_owner_record(dir.path()).unwrap().unwrap(),
        RuntimeOwnerRecord::new(replacement)
    );
}

#[test]
fn pid_reuse_proves_the_recorded_owner_exited() {
    let dir = tempfile::tempdir().unwrap();
    let old = identity(100, 1_000);
    let reused = identity(100, 9_000);
    let replacement = identity(200, 2_000);
    write_owner_record(dir.path(), &RuntimeOwnerRecord::new(old)).unwrap();
    let reused_probe = probe([(old.pid, ProcessLookup::Live(reused))]);

    let _guard =
        RuntimeOwnerGuard::acquire_with_probe(dir.path(), replacement, &reused_probe).unwrap();

    assert_eq!(
        read_owner_record(dir.path()).unwrap().unwrap(),
        RuntimeOwnerRecord::new(replacement)
    );
}

#[test]
fn handoff_rejects_missing_owner_metadata() {
    let dir = tempfile::tempdir().unwrap();
    let expected = RuntimeOwnerIdentity {
        pid: 100,
        start_marker: 1_000,
    };

    let error = RuntimeOwnerGuard::acquire_handoff_with_probe(
        dir.path(),
        expected,
        identity(200, 2_000),
        &probe([]),
    )
    .err()
    .expect("a handoff without owner metadata should be rejected");

    assert!(error
        .to_string()
        .contains("owner metadata is not available"));
    assert!(!dir.path().join(OWNER_FILE_NAME).exists());
}

#[test]
fn handoff_rejects_a_mismatched_owner_identity_without_rewriting_metadata() {
    let dir = tempfile::tempdir().unwrap();
    let old = identity(100, 1_000);
    write_owner_record(dir.path(), &RuntimeOwnerRecord::new(old)).unwrap();
    let before = std::fs::read(dir.path().join(OWNER_FILE_NAME)).unwrap();

    let error = RuntimeOwnerGuard::acquire_handoff_with_probe(
        dir.path(),
        RuntimeOwnerIdentity {
            pid: old.pid,
            start_marker: 9_000,
        },
        identity(200, 2_000),
        &probe([(old.pid, ProcessLookup::Exited)]),
    )
    .err()
    .expect("a mismatched handoff should be rejected");

    assert!(error.to_string().contains("refusing replacement"));
    assert_eq!(
        std::fs::read(dir.path().join(OWNER_FILE_NAME)).unwrap(),
        before
    );
}

#[test]
fn handoff_rejects_an_owner_change_at_the_lock_boundary() {
    let dir = tempfile::tempdir().unwrap();
    let expected = identity(100, 1_000);
    let intervening_owner = identity(300, 3_000);
    let handoff = RuntimeOwnerIdentity::from(expected);
    write_owner_record(dir.path(), &RuntimeOwnerRecord::new(expected)).unwrap();
    validate_handoff_owner(dir.path(), handoff).unwrap();
    let lock = open_lock_file(&dir.path().join(LOCK_FILE_NAME)).unwrap();
    lock.lock().unwrap();

    write_owner_record(dir.path(), &RuntimeOwnerRecord::new(intervening_owner)).unwrap();
    let error = finish_handoff(
        dir.path(),
        handoff,
        identity(200, 2_000),
        &probe([(expected.pid, ProcessLookup::Exited)]),
        lock,
    )
    .err()
    .expect("a handoff must not cross into a different owner's tenure");

    assert!(error.to_string().contains("refusing replacement"));
    assert_eq!(
        read_owner_record(dir.path()).unwrap().unwrap(),
        RuntimeOwnerRecord::new(intervening_owner)
    );
}

#[test]
fn handoff_fails_closed_when_the_expected_owner_cannot_be_validated() {
    let dir = tempfile::tempdir().unwrap();
    let old = identity(100, 1_000);
    write_owner_record(dir.path(), &RuntimeOwnerRecord::new(old)).unwrap();
    let before = std::fs::read(dir.path().join(OWNER_FILE_NAME)).unwrap();

    let error = RuntimeOwnerGuard::acquire_handoff_with_probe(
        dir.path(),
        RuntimeOwnerIdentity::from(old),
        identity(200, 2_000),
        &probe([(old.pid, ProcessLookup::Unknown("access denied".to_string()))]),
    )
    .err()
    .expect("an unverifiable handoff should be rejected");

    assert!(error.to_string().contains("could not be validated"));
    assert_eq!(
        std::fs::read(dir.path().join(OWNER_FILE_NAME)).unwrap(),
        before
    );
}

#[test]
fn handoff_accepts_pid_reuse_only_for_the_exact_recorded_owner() {
    let dir = tempfile::tempdir().unwrap();
    let old = identity(100, 1_000);
    let reused = identity(100, 9_000);
    let replacement = identity(200, 2_000);
    write_owner_record(dir.path(), &RuntimeOwnerRecord::new(old)).unwrap();

    let _guard = RuntimeOwnerGuard::acquire_handoff_with_probe(
        dir.path(),
        RuntimeOwnerIdentity::from(old),
        replacement,
        &probe([(old.pid, ProcessLookup::Live(reused))]),
    )
    .unwrap();

    assert_eq!(
        read_owner_record(dir.path()).unwrap().unwrap(),
        RuntimeOwnerRecord::new(replacement)
    );
}

#[test]
fn unverifiable_stale_owner_fails_closed() {
    let dir = tempfile::tempdir().unwrap();
    let old = identity(100, 1_000);
    write_owner_record(dir.path(), &RuntimeOwnerRecord::new(old)).unwrap();
    let unknown_probe = probe([(old.pid, ProcessLookup::Unknown("access denied".to_string()))]);

    let error =
        RuntimeOwnerGuard::acquire_with_probe(dir.path(), identity(200, 2_000), &unknown_probe)
            .err()
            .expect("unverifiable owner should be rejected");

    assert!(error.to_string().contains("refusing stale-owner recovery"));
    assert_eq!(
        read_owner_record(dir.path()).unwrap().unwrap(),
        RuntimeOwnerRecord::new(old)
    );
}

#[test]
fn malformed_owner_metadata_is_never_overwritten() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join(OWNER_FILE_NAME);
    std::fs::write(&path, b"not json").unwrap();

    let error = RuntimeOwnerGuard::acquire_with_probe(dir.path(), identity(200, 2_000), &probe([]))
        .err()
        .expect("malformed ownership should be rejected");

    assert!(error.to_string().contains("is invalid"));
    assert_eq!(std::fs::read(path).unwrap(), b"not json");
}

#[cfg(unix)]
#[test]
fn ownership_files_are_private() {
    use std::os::unix::fs::PermissionsExt as _;

    let dir = tempfile::tempdir().unwrap();
    let owner = identity(100, 1_000);
    let _guard = RuntimeOwnerGuard::acquire_with_probe(
        dir.path(),
        owner,
        &probe([(owner.pid, ProcessLookup::Live(owner))]),
    )
    .unwrap();

    for name in [LOCK_FILE_NAME, OWNER_FILE_NAME] {
        assert_eq!(
            std::fs::metadata(dir.path().join(name))
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o600
        );
    }
}
