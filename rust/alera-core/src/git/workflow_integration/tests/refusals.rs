use super::*;

#[test]
fn submodule_delta_is_a_terminal_pre_apply_refusal_without_git_receipt() {
    let fixture = Fixture::new();
    let mut request = fixture.request(&[("result.txt", "done\n")]);
    let source = Repository::open(&fixture.source.path).unwrap();
    let module_path = Path::new(&fixture.source.path).join("module");
    let module = Repository::init(&module_path).unwrap();
    let signature = git2::Signature::now("Workflow Test", "workflow@example.invalid").unwrap();
    let empty_tree = module
        .find_tree(module.treebuilder(None).unwrap().write().unwrap())
        .unwrap();
    let module_sha = module
        .commit(
            Some("HEAD"),
            &signature,
            &signature,
            "test: module",
            &empty_tree,
            &[],
        )
        .unwrap();
    let parent = source.head().unwrap().peel_to_commit().unwrap();
    let mut builder = source.treebuilder(Some(&parent.tree().unwrap())).unwrap();
    builder.insert("module", module_sha, 0o160000).unwrap();
    let tree = source.find_tree(builder.write().unwrap()).unwrap();
    request.source_sha = source
        .commit(
            Some("HEAD"),
            &signature,
            &signature,
            "test: add module",
            &tree,
            &[&parent],
        )
        .unwrap()
        .to_string();
    let mut index = source.index().unwrap();
    index.add_path(Path::new("module")).unwrap();
    index.write().unwrap();

    let integration = Repository::open(&fixture.integration.path).unwrap();
    let original_head = head_oid(&integration).unwrap();
    let original_index = fs::read(integration.path().join("index")).unwrap();
    let outcome = prepare_workflow_integration(&request).unwrap();
    assert!(matches!(outcome, WorkflowGitPreparation::Refused {
        paths, truncated: false, reason
    } if paths == ["module"] && reason.contains("submodule changes")));
    assert_eq!(head_oid(&integration).unwrap(), original_head);
    assert_eq!(
        fs::read(integration.path().join("index")).unwrap(),
        original_index
    );
    assert!(!Path::new(&fixture.integration.path).join("module").exists());
    assert!(integration
        .find_reference(&format!("refs/alera/workflow-integrations/{}", request.id))
        .is_err());
    assert!(receipt::load(&integration, &request).unwrap().is_none());
}
