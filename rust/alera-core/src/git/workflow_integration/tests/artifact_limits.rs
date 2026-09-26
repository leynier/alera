use super::*;

#[test]
fn committed_artifact_preflight_accepts_128_and_rejects_129() {
    let fixture = Fixture::new();
    let paths = (0..MAX_WORKFLOW_ARTIFACTS)
        .map(|index| format!("artifacts/{index}.txt"))
        .collect::<Vec<_>>();
    let changes = paths
        .iter()
        .map(|path| (path.as_str(), "committed\n"))
        .collect::<Vec<_>>();
    let sha = commit(Path::new(&fixture.source.path), &changes);
    validate_workflow_artifacts(&fixture.source.path, &sha, &paths).unwrap();

    let mut excessive = paths;
    excessive.push("artifacts/overflow.txt".into());
    assert!(
        validate_workflow_artifacts(&fixture.source.path, &sha, &excessive)
            .unwrap_err()
            .to_string()
            .contains("too many artifacts")
    );
}
