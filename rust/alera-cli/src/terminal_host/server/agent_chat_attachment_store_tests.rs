use super::*;

fn scope() -> AttachmentScope {
    AttachmentScope {
        caller: "mobile:phone".into(),
        workspace_id: "workspace".into(),
        chat_id: "chat".into(),
    }
}

fn start(store: &ChatAttachmentStore, id: &str, size: u64) -> Value {
    store
        .start(
            &scope(),
            id,
            &spec("report.md", size),
            &HashSet::from(["chat".into()]),
        )
        .expect("start")
}

fn spec(name: &str, size_bytes: u64) -> AttachmentUploadSpec<'_> {
    AttachmentUploadSpec {
        name,
        attachment_type: "file",
        size_bytes,
        source_digest: None,
    }
}

#[test]
fn reconnect_replays_exact_chunks_and_completed_receipts_without_new_files() {
    let root = tempfile::tempdir().unwrap();
    let id = Uuid::new_v4().to_string();
    let store = ChatAttachmentStore::in_runtime_dir(root.path());
    assert_eq!(start(&store, &id, 5)["offset"], 0);
    assert_eq!(store.append(&scope(), &id, 0, b"hel").unwrap(), 3);
    let restarted = ChatAttachmentStore::in_runtime_dir(root.path());
    assert_eq!(start(&restarted, &id, 5)["offset"], 3);
    assert_eq!(restarted.append(&scope(), &id, 0, b"hel").unwrap(), 3);
    assert!(restarted.append(&scope(), &id, 0, b"bad").is_err());
    assert_eq!(restarted.append(&scope(), &id, 3, b"lo").unwrap(), 5);
    let receipt = restarted.complete(&scope(), &id).unwrap();
    assert_eq!(restarted.complete(&scope(), &id).unwrap(), receipt);
    assert_eq!(start(&restarted, &id, 5)["complete"], true);
    assert_eq!(
        std::fs::read(receipt["path"].as_str().unwrap()).unwrap(),
        b"hello"
    );
    assert_eq!(restarted.append(&scope(), &id, 0, b"hello").unwrap(), 5);
}

#[test]
fn source_digest_rejects_same_size_changes_on_resume_and_during_transfer() {
    let root = tempfile::tempdir().unwrap();
    let store = ChatAttachmentStore::in_runtime_dir(root.path());
    let id = Uuid::new_v4().to_string();
    let live = HashSet::from(["chat".into()]);
    let original = hex::encode(Sha256::digest(b"hello"));
    let changed = hex::encode(Sha256::digest(b"world"));
    let original_spec = AttachmentUploadSpec {
        source_digest: Some(&original),
        ..spec("report.md", 5)
    };
    store.start(&scope(), &id, &original_spec, &live).unwrap();
    store.append(&scope(), &id, 0, b"hel").unwrap();
    assert!(store
        .start(
            &scope(),
            &id,
            &AttachmentUploadSpec {
                source_digest: Some(&changed),
                ..spec("report.md", 5)
            },
            &live
        )
        .is_err());
    store.append(&scope(), &id, 3, b"xx").unwrap();
    assert!(store.complete(&scope(), &id).is_err());
    assert!(!store.metadata_path(&id).exists());
    store.start(&scope(), &id, &original_spec, &live).unwrap();
    store.append(&scope(), &id, 0, b"hello").unwrap();
    assert!(store.complete(&scope(), &id).is_ok());
}

#[test]
fn scope_binds_all_upload_operations_to_originating_human_workspace_and_chat() {
    let root = tempfile::tempdir().unwrap();
    let store = ChatAttachmentStore::in_runtime_dir(root.path());
    let id = Uuid::new_v4().to_string();
    start(&store, &id, 1);
    store.append(&scope(), &id, 0, b"x").unwrap();
    store.complete(&scope(), &id).unwrap();
    for other in [
        AttachmentScope {
            caller: "desktop".into(),
            ..scope()
        },
        AttachmentScope {
            workspace_id: "elsewhere".into(),
            ..scope()
        },
        AttachmentScope {
            chat_id: "other-chat".into(),
            ..scope()
        },
    ] {
        assert!(store.append(&other, &id, 0, b"x").is_err());
        assert!(store.complete(&other, &id).is_err());
        assert!(store.cancel(&other, &id).is_err());
        assert!(store.resolve(&other, &id).is_err());
    }
    assert!(store.resolve(&scope(), &id).is_ok());
}

#[test]
fn cancellation_and_cleanup_preserve_native_inputs_until_the_chat_is_deleted() {
    let root = tempfile::tempdir().unwrap();
    let store = ChatAttachmentStore::in_runtime_dir(root.path());
    let unused = Uuid::new_v4().to_string();
    start(&store, &unused, 1);
    store.cancel(&scope(), &unused).unwrap();
    store.cancel(&scope(), &unused).unwrap();
    assert!(!store.metadata_path(&unused).exists());
    let used = Uuid::new_v4().to_string();
    start(&store, &used, 1);
    store.append(&scope(), &used, 0, b"x").unwrap();
    store.complete(&scope(), &used).unwrap();
    let receipt = store.resolve(&scope(), &used).unwrap();
    store.cancel(&scope(), &used).unwrap();
    assert!(Path::new(receipt["path"].as_str().unwrap()).exists());
    store.sweep(&HashSet::from(["chat".into()])).unwrap();
    assert!(store.resolve(&scope(), &used).is_ok());
    store.sweep(&HashSet::new()).unwrap();
    assert!(!Path::new(receipt["path"].as_str().unwrap()).exists());
}

#[test]
fn unused_completed_uploads_expire_after_twenty_four_hours() {
    let root = tempfile::tempdir().unwrap();
    let store = ChatAttachmentStore::in_runtime_dir(root.path());
    let id = Uuid::new_v4().to_string();
    start(&store, &id, 1);
    let mut metadata = store.read(&scope(), &id).unwrap();
    metadata.created_at -= chrono::Duration::hours(25);
    std::fs::write(
        store.metadata_path(&id),
        serde_json::to_vec(&metadata).unwrap(),
    )
    .unwrap();
    assert!(store.append(&scope(), &id, 0, b"x").is_err());
    store.sweep(&HashSet::from(["chat".into()])).unwrap();
    assert!(!store.metadata_path(&id).exists());
}

#[test]
fn uploads_reject_traversal_oversize_mismatched_retries_and_reservation_quota() {
    let root = tempfile::tempdir().unwrap();
    let store = ChatAttachmentStore::in_runtime_dir(root.path());
    let live = HashSet::from(["chat".into()]);
    for name in [
        "../outside",
        "..\\outside",
        ".",
        "..",
        "bad\0name",
        "a\nname",
    ] {
        assert!(store
            .start(&scope(), &Uuid::new_v4().to_string(), &spec(name, 1), &live)
            .is_err());
    }
    assert!(store
        .start(&scope(), "../outside", &spec("report", 1), &live)
        .is_err());
    assert!(store
        .start(
            &scope(),
            &Uuid::new_v4().to_string(),
            &spec("large", MAX_FILE_BYTES + 1),
            &live
        )
        .is_err());
    let id = Uuid::new_v4().to_string();
    start(&store, &id, 1);
    assert!(store.append(&scope(), &id, 0, b"xx").is_err());
    assert!(store
        .append(&scope(), &id, 0, &vec![0; CHUNK_BYTES + 1])
        .is_err());
    assert!(store.complete(&scope(), &id).is_err());
    assert!(store
        .start(&scope(), &id, &spec("other", 1), &live)
        .is_err());
    store.cancel(&scope(), &id).unwrap();
    for _ in 0..4 {
        start(&store, &Uuid::new_v4().to_string(), MAX_FILE_BYTES);
    }
    assert!(store
        .start(
            &scope(),
            &Uuid::new_v4().to_string(),
            &spec("overflow", 1),
            &live
        )
        .is_err());
}

#[test]
fn reserved_extension_cannot_overwrite_metadata_or_retention_markers() {
    let root = tempfile::tempdir().unwrap();
    let store = ChatAttachmentStore::in_runtime_dir(root.path());
    for name in ["report.meta", "report.partial", "report.retained"] {
        let id = Uuid::new_v4().to_string();
        store
            .start(
                &scope(),
                &id,
                &spec(name, 1),
                &HashSet::from(["chat".into()]),
            )
            .unwrap();
        store.append(&scope(), &id, 0, b"x").unwrap();
        store.complete(&scope(), &id).unwrap();
        assert!(store.resolve(&scope(), &id).is_ok());
    }
}

#[cfg(unix)]
#[test]
fn symlinked_stores_or_payloads_are_rejected_without_touching_the_target() {
    use std::os::unix::fs::symlink;
    let root = tempfile::tempdir().unwrap();
    let outside = tempfile::tempdir().unwrap();
    symlink(outside.path(), root.path().join("agent-chat-attachments")).unwrap();
    let store = ChatAttachmentStore::in_runtime_dir(root.path());
    assert!(store
        .start(
            &scope(),
            &Uuid::new_v4().to_string(),
            &spec("x", 1),
            &HashSet::from(["chat".into()])
        )
        .is_err());
    std::fs::remove_file(root.path().join("agent-chat-attachments")).unwrap();
    let id = Uuid::new_v4().to_string();
    start(&store, &id, 1);
    let target = outside.path().join("target");
    std::fs::write(&target, b"secret").unwrap();
    std::fs::remove_file(store.partial_path(&id)).unwrap();
    symlink(&target, store.partial_path(&id)).unwrap();
    assert!(store.append(&scope(), &id, 0, b"x").is_err());
    assert_eq!(std::fs::read(&target).unwrap(), b"secret");
}
