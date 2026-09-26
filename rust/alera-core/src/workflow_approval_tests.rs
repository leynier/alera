use super::*;

fn directory() -> tempfile::TempDir {
    let directory = tempfile::tempdir().unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(directory.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    }
    directory
}

fn statement() -> WorkflowApprovalStatement {
    WorkflowApprovalStatement {
        challenge: WorkflowApprovalChallenge {
            version: 1,
            nonce: "nonce".into(),
            audience: "boot:client".into(),
            run_id: "run".into(),
            revision: 1,
            scope: "plan".into(),
            plan_digest: "digest".into(),
            evidence_digest: "evidence".into(),
            integration_sha: "sha".into(),
            expires_at: 100,
        },
        decision: WorkflowDecision::Approve,
        reason: String::new(),
    }
}

#[test]
fn workflow_approval_is_bound_to_all_statement_fields() {
    let dir = directory();
    let key = DesktopWorkflowCredential::load_or_create(dir.path()).unwrap();
    let original = statement();
    let proof = key.sign(&original).unwrap();
    key.verify(original.clone(), &proof).unwrap();
    let mut candidates = Vec::new();
    let mut changed = original.clone();
    changed.challenge.revision += 1;
    candidates.push(changed);
    let mut changed = original.clone();
    changed.challenge.audience.push('x');
    candidates.push(changed);
    let mut changed = original.clone();
    changed.challenge.integration_sha.push('x');
    candidates.push(changed);
    let mut changed = original.clone();
    changed.challenge.evidence_digest.push('x');
    candidates.push(changed);
    let mut changed = original.clone();
    changed.challenge.plan_digest.push('x');
    candidates.push(changed);
    let mut changed = original.clone();
    changed.challenge.scope.push('x');
    candidates.push(changed);
    let mut changed = original.clone();
    changed.challenge.nonce.push('x');
    candidates.push(changed);
    let mut changed = original.clone();
    changed.decision = WorkflowDecision::Reject;
    changed.reason = "changes".into();
    candidates.push(changed);
    for changed in candidates {
        assert!(key.verify(changed, &proof).is_err());
    }
    assert!(key
        .verify(original.clone(), b"shared-runtime-token")
        .is_err());
    let other = directory();
    let other_key = DesktopWorkflowCredential::load_or_create(other.path()).unwrap();
    assert!(other_key.verify(original.clone(), &proof).is_err());
    let reloaded = DesktopWorkflowCredential::load_or_create(dir.path()).unwrap();
    reloaded.verify(original, &proof).unwrap();
}

#[test]
fn workflow_credential_creation_is_atomic_and_concurrent() {
    let dir = directory();
    std::thread::scope(|scope| {
        let jobs = (0..12)
            .map(|_| {
                scope.spawn(|| {
                    DesktopWorkflowCredential::load_or_create(dir.path())
                        .unwrap()
                        .sign(&statement())
                        .unwrap()
                })
            })
            .collect::<Vec<_>>();
        let proofs = jobs
            .into_iter()
            .map(|job| job.join().unwrap())
            .collect::<Vec<_>>();
        assert!(proofs.windows(2).all(|pair| pair[0] == pair[1]));
    });
    assert_eq!(std::fs::read_dir(dir.path()).unwrap().count(), 1);
}

#[test]
fn workflow_approval_rejects_oversized_and_empty_rejection() {
    let mut input = statement();
    input.reason = "x".repeat(4097);
    assert!(input.message().is_err());
    input.reason.clear();
    input.decision = WorkflowDecision::RequestChanges;
    assert!(input.message().is_err());
}

#[cfg(unix)]
#[test]
fn workflow_credential_rejects_symlinks_and_public_files() {
    use std::os::unix::fs::{symlink, PermissionsExt};
    let dir = directory();
    let outside = tempfile::NamedTempFile::new().unwrap();
    symlink(outside.path(), dir.path().join(KEY_FILE)).unwrap();
    assert!(DesktopWorkflowCredential::load_or_create(dir.path()).is_err());
    std::fs::remove_file(dir.path().join(KEY_FILE)).unwrap();
    DesktopWorkflowCredential::load_or_create(dir.path()).unwrap();
    std::fs::set_permissions(
        dir.path().join(KEY_FILE),
        std::fs::Permissions::from_mode(0o644),
    )
    .unwrap();
    assert!(DesktopWorkflowCredential::load_or_create(dir.path()).is_err());
}
