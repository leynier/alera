use super::workflow_export::export_at;
use super::{builtin_workflow_recipes, WorkflowExportRequest};

fn request() -> WorkflowExportRequest {
    WorkflowExportRequest {
        workspace_id: "workspace".into(),
        filename: "quick-fix.yaml".into(),
        document: builtin_workflow_recipes()[0].portable_document().unwrap(),
        expected_digest: None,
    }
}

#[test]
fn workflow_export_preview_is_read_only_and_apply_requires_exact_review() {
    let root = tempfile::tempdir().unwrap();
    let mut request = request();
    let preview = export_at(root.path(), "instance", request.clone(), false).unwrap();
    assert!(!root.path().join(".alera").exists());
    assert!(export_at(root.path(), "instance", request.clone(), true).is_err());
    request.expected_digest = Some(preview.expected_digest.clone());
    export_at(root.path(), "instance", request.clone(), true).unwrap();
    let path = root.path().join(".alera/workflows/quick-fix.yaml");
    assert_eq!(std::fs::read_to_string(&path).unwrap(), preview.after);
    std::fs::write(&path, "external edit").unwrap();
    assert!(export_at(root.path(), "instance", request, true).is_err());
    assert_eq!(std::fs::read_to_string(path).unwrap(), "external edit");
}

#[test]
fn workflow_export_binds_workspace_instance_filename_and_document() {
    let root = tempfile::tempdir().unwrap();
    let mut request = request();
    let preview = export_at(root.path(), "instance", request.clone(), false).unwrap();
    request.expected_digest = Some(preview.expected_digest);
    assert!(export_at(root.path(), "replacement", request.clone(), true).is_err());
    request.filename = "other.yaml".into();
    assert!(export_at(root.path(), "instance", request.clone(), true).is_err());
    request.filename = "quick-fix.yaml".into();
    request.document = builtin_workflow_recipes()[1].portable_document().unwrap();
    assert!(export_at(root.path(), "instance", request, true).is_err());
    assert!(!root.path().join(".alera").exists());
}

#[test]
fn workflow_export_replaces_reviewed_bytes_and_preserves_original() {
    let root = tempfile::tempdir().unwrap();
    let directory = root.path().join(".alera/workflows");
    std::fs::create_dir_all(&directory).unwrap();
    std::fs::write(directory.join("quick-fix.yaml"), "old content").unwrap();
    let mut request = request();
    let preview = export_at(root.path(), "instance", request.clone(), false).unwrap();
    assert_eq!(preview.before.as_deref(), Some("old content"));
    request.expected_digest = Some(preview.expected_digest);
    export_at(root.path(), "instance", request, true).unwrap();
    assert_eq!(
        std::fs::read_to_string(directory.join("quick-fix.yaml")).unwrap(),
        preview.after
    );
    let retained = std::fs::read_dir(directory)
        .unwrap()
        .map(|e| e.unwrap().path())
        .find(|p| p.extension().is_some_and(|e| e == "bak"))
        .unwrap();
    assert_eq!(std::fs::read_to_string(retained).unwrap(), "old content");
}

#[test]
fn workflow_export_rejects_unsafe_portable_filenames() {
    let root = tempfile::tempdir().unwrap();
    for name in [
        "../escape.yaml",
        "/escape.yaml",
        "nested/file.yaml",
        "NUL.yaml",
        "x.yml",
        ".hidden.yaml",
    ] {
        let mut request = request();
        request.filename = name.into();
        assert!(
            export_at(root.path(), "instance", request, false).is_err(),
            "{name}"
        );
    }
}

#[cfg(unix)]
#[test]
fn workflow_export_never_follows_directory_or_file_symlinks() {
    let root = tempfile::tempdir().unwrap();
    let outside = tempfile::tempdir().unwrap();
    std::os::unix::fs::symlink(outside.path(), root.path().join(".alera")).unwrap();
    assert!(export_at(root.path(), "instance", request(), false).is_err());
    assert_eq!(std::fs::read_dir(outside.path()).unwrap().count(), 0);
}
