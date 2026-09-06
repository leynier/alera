use super::*;

#[test]
fn workflow_integration_respects_crlf_checkout_without_changing_blob_bytes() {
    let fixture = Fixture::with_autocrlf(true);
    let request = fixture.request(&[("result.txt", "done\n")]);
    let receipt = prepared(&request);
    assert_eq!(apply_workflow_integration(&request).unwrap(), receipt);
    assert_eq!(
        fs::read_to_string(Path::new(&fixture.integration.path).join("result.txt")).unwrap(),
        "done\r\n"
    );
    let repo = Repository::open(&fixture.integration.path).unwrap();
    let commit = repo
        .find_commit(oid(&receipt.integrated_sha).unwrap())
        .unwrap();
    let tree = commit.tree().unwrap();
    let entry = tree.get_path(Path::new("result.txt")).unwrap();
    assert_eq!(repo.find_blob(entry.id()).unwrap().content(), b"done\n");
    assert!(is_worktree_clean(&fixture.integration.path).unwrap());
    assert_eq!(apply_workflow_integration(&request).unwrap(), receipt);
}
