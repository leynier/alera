use super::*;

const PNG: &[u8] = b"\x89PNG\r\n\x1a\nthumbnail-bytes";

fn scope(caller: &str) -> AttachmentScope {
    AttachmentScope {
        caller: caller.into(),
        workspace_id: "workspace".into(),
        chat_id: "chat".into(),
    }
}

/// Uploads [bytes] as [name] from `desktop`; [send] marks it consumed.
fn upload(store: &ChatAttachmentStore, name: &str, bytes: &[u8], send: bool) -> String {
    let id = Uuid::new_v4().to_string();
    let spec = AttachmentUploadSpec {
        name,
        attachment_type: "localImage",
        size_bytes: bytes.len() as u64,
        source_digest: None,
    };
    let live = HashSet::from(["chat".into()]);
    store.start(&scope("desktop"), &id, &spec, &live).unwrap();
    store.append(&scope("desktop"), &id, 0, bytes).unwrap();
    store.complete(&scope("desktop"), &id).unwrap();
    if send {
        store.resolve(&scope("desktop"), &id).unwrap();
    }
    id
}

fn read(
    store: &ChatAttachmentStore,
    chat_id: &str,
    caller: &str,
    id: &str,
    offset: u64,
) -> HostResult<Value> {
    store.read_piece(&AttachmentRead {
        workspace_id: "workspace",
        chat_id,
        caller,
        attachment_id: id,
        offset,
        length: READ_PIECE_BYTES,
    })
}

fn code(result: HostResult<Value>) -> String {
    match result {
        Err(HostError::Conflict { code, .. }) => code,
        Err(other) => format!("unexpected error: {}", other.wire_message()),
        Ok(_) => "unexpected success".into(),
    }
}

#[test]
fn a_sent_image_reads_back_in_pieces_for_any_reader_of_the_chat() {
    let root = tempfile::tempdir().unwrap();
    let store = ChatAttachmentStore::in_runtime_dir(root.path());
    let id = upload(&store, "photo.png", PNG, true);
    let piece = read(&store, "chat", "mobile:phone", &id, 0).unwrap();
    assert_eq!(piece["attachmentId"], id.as_str());
    assert_eq!(piece["mimeType"], "image/png");
    assert_eq!(piece["sizeBytes"], PNG.len());
    assert_eq!(piece["offset"], 0);
    assert_eq!(piece["nextOffset"], PNG.len());
    assert_eq!(
        STANDARD
            .decode(piece["dataBase64"].as_str().unwrap())
            .unwrap(),
        PNG
    );
    let tail = read(&store, "chat", "desktop", &id, 8).unwrap();
    assert_eq!(
        STANDARD
            .decode(tail["dataBase64"].as_str().unwrap())
            .unwrap(),
        &PNG[8..]
    );
    assert!(read(&store, "chat", "desktop", &id, PNG.len() as u64 + 1).is_err());
}

#[test]
fn another_chat_or_an_unsent_upload_of_another_person_is_refused() {
    let root = tempfile::tempdir().unwrap();
    let store = ChatAttachmentStore::in_runtime_dir(root.path());
    let sent = upload(&store, "photo.png", PNG, true);
    assert_eq!(
        code(read(&store, "other-chat", "desktop", &sent, 0)),
        "attachment_scope_denied"
    );
    let unsent = upload(&store, "draft.png", PNG, false);
    assert!(read(&store, "chat", "desktop", &unsent, 0).is_ok());
    assert_eq!(
        code(read(&store, "chat", "mobile:phone", &unsent, 0)),
        "attachment_scope_denied"
    );
}

#[test]
fn attachments_over_the_preview_cap_are_refused() {
    let root = tempfile::tempdir().unwrap();
    let store = ChatAttachmentStore::in_runtime_dir(root.path());
    let id = Uuid::new_v4().to_string();
    let spec = AttachmentUploadSpec {
        name: "huge.png",
        attachment_type: "localImage",
        size_bytes: MAX_READ_BYTES + 1,
        source_digest: None,
    };
    store
        .start(
            &scope("desktop"),
            &id,
            &spec,
            &HashSet::from(["chat".into()]),
        )
        .unwrap();
    assert_eq!(
        code(read(&store, "chat", "desktop", &id, 0)),
        "attachment_too_large"
    );
}

#[test]
fn non_media_attachments_are_refused_by_their_bytes_not_their_name() {
    let root = tempfile::tempdir().unwrap();
    let store = ChatAttachmentStore::in_runtime_dir(root.path());
    let id = upload(&store, "notes.png", b"#!/bin/sh\necho not an image\n", true);
    assert_eq!(
        code(read(&store, "chat", "desktop", &id, 0)),
        "attachment_unsupported_type"
    );
    assert_eq!(media_mime_type(b"\0\0\0\x18ftypmp42"), Some("video/mp4"));
    assert_eq!(
        media_mime_type(b"\0\0\0\x14ftypqt  "),
        Some("video/quicktime")
    );
    assert_eq!(media_mime_type(b"\0\0\0\x18ftypheic"), Some("image/heic"));
    assert_eq!(
        media_mime_type(&[0x1a, 0x45, 0xdf, 0xa3]),
        Some("video/webm")
    );
    assert_eq!(media_mime_type(b"%PDF-1.7"), None);
}

#[test]
fn ids_that_could_name_other_paths_are_refused() {
    let root = tempfile::tempdir().unwrap();
    let store = ChatAttachmentStore::in_runtime_dir(root.path());
    upload(&store, "photo.png", PNG, true);
    std::fs::write(root.path().join("secret.meta"), b"{}").unwrap();
    for id in [
        "../secret",
        "..",
        "/etc/passwd",
        "a/b",
        "..\\secret",
        "",
        "00000000-0000-0000-0000-00000000000G",
    ] {
        assert_eq!(
            code(read(&store, "chat", "desktop", id, 0)),
            "attachment_not_found"
        );
    }
    let missing = Uuid::new_v4().to_string();
    assert_eq!(
        code(read(&store, "chat", "desktop", &missing, 0)),
        "attachment_not_found"
    );
}

#[cfg(unix)]
#[test]
fn symlinks_out_of_the_store_are_never_followed() {
    use std::os::unix::fs::symlink;
    let root = tempfile::tempdir().unwrap();
    let outside = tempfile::tempdir().unwrap();
    let store = ChatAttachmentStore::in_runtime_dir(root.path());
    let id = upload(&store, "photo.png", PNG, true);
    let target = outside.path().join("target.png");
    std::fs::write(&target, PNG).unwrap();
    let data = std::fs::read_dir(root.path().join("agent-chat-attachments"))
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .find(|path| path.to_string_lossy().contains(".data."))
        .unwrap();
    std::fs::remove_file(&data).unwrap();
    symlink(&target, &data).unwrap();
    assert!(read(&store, "chat", "desktop", &id, 0).is_err());

    let moved = root.path().join("moved");
    std::fs::rename(root.path().join("agent-chat-attachments"), &moved).unwrap();
    symlink(&moved, root.path().join("agent-chat-attachments")).unwrap();
    assert_eq!(
        code(read(&store, "chat", "desktop", &id, 0)),
        "attachment_not_found"
    );
}
