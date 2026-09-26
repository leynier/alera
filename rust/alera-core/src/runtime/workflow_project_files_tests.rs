use std::fs;

use super::workflow_project_files::read_project_workflow_documents;
use super::WORKFLOW_DOCUMENT_MAX_BYTES;

#[test]
fn workflow_project_files_read_only_direct_yaml_with_per_file_errors() {
    let root = tempfile::tempdir().unwrap();
    assert!(read_project_workflow_documents(root.path())
        .unwrap()
        .is_empty());
    let catalog = root.path().join(".alera/workflows");
    fs::create_dir_all(catalog.join("nested")).unwrap();
    fs::write(catalog.join("a.yaml"), "name: A").unwrap();
    fs::write(catalog.join("b.yaml"), [0xff]).unwrap();
    fs::write(catalog.join("ignore.yml"), "ignored").unwrap();
    fs::write(catalog.join("nested/hidden.yaml"), "ignored").unwrap();
    let documents = read_project_workflow_documents(root.path()).unwrap();
    assert_eq!(documents.len(), 2);
    assert_eq!(documents[0].path, ".alera/workflows/a.yaml");
    assert_eq!(documents[0].source.as_ref().unwrap(), "name: A");
    assert!(documents[1].source.is_err());
}

#[test]
fn workflow_project_files_bound_file_and_catalog_sizes() {
    let root = tempfile::tempdir().unwrap();
    let catalog = root.path().join(".alera/workflows");
    fs::create_dir_all(&catalog).unwrap();
    fs::write(
        catalog.join("large.yaml"),
        vec![b'a'; WORKFLOW_DOCUMENT_MAX_BYTES + 1],
    )
    .unwrap();
    assert!(read_project_workflow_documents(root.path()).unwrap()[0]
        .source
        .is_err());
    for index in 0..128 {
        fs::write(catalog.join(format!("{index}.yaml")), "name: A").unwrap();
    }
    assert!(read_project_workflow_documents(root.path()).is_err());
}

#[test]
fn workflow_project_files_bound_total_bytes_and_directory_enumeration() {
    let root = tempfile::tempdir().unwrap();
    let catalog = root.path().join(".alera/workflows");
    fs::create_dir_all(&catalog).unwrap();
    for index in 0..33 {
        fs::write(
            catalog.join(format!("{index}.yaml")),
            vec![b'a'; WORKFLOW_DOCUMENT_MAX_BYTES],
        )
        .unwrap();
    }
    assert!(read_project_workflow_documents(root.path())
        .unwrap_err()
        .to_string()
        .contains("byte limit"));
    let other = tempfile::tempdir().unwrap();
    let catalog = other.path().join(".alera/workflows");
    fs::create_dir_all(&catalog).unwrap();
    for index in 0..2049 {
        fs::write(catalog.join(format!("{index}.txt")), "").unwrap();
    }
    assert!(read_project_workflow_documents(other.path())
        .unwrap_err()
        .to_string()
        .contains("entry limit"));
}

#[cfg(unix)]
#[test]
fn workflow_project_files_reject_file_and_parent_symlink_escapes() {
    use std::os::unix::fs::symlink;
    let root = tempfile::tempdir().unwrap();
    let outside = tempfile::tempdir().unwrap();
    fs::write(outside.path().join("secret.yaml"), "secret: hidden").unwrap();
    fs::create_dir_all(root.path().join(".alera")).unwrap();
    symlink(outside.path(), root.path().join(".alera/workflows")).unwrap();
    assert!(read_project_workflow_documents(root.path()).is_err());
    fs::remove_file(root.path().join(".alera/workflows")).unwrap();
    fs::create_dir(root.path().join(".alera/workflows")).unwrap();
    symlink(
        outside.path().join("secret.yaml"),
        root.path().join(".alera/workflows/escape.yaml"),
    )
    .unwrap();
    assert!(read_project_workflow_documents(root.path()).unwrap()[0]
        .source
        .is_err());
    let other = tempfile::tempdir().unwrap();
    symlink(root.path().join(".alera"), other.path().join(".alera")).unwrap();
    assert!(read_project_workflow_documents(other.path()).is_err());
}
