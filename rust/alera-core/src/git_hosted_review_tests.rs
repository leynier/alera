use std::fs;

use git2::{BranchType, IndexAddOption, Oid, Repository, Signature};

use super::{fetch_hosted_review_range, release_hosted_review_range};

#[test]
fn fetches_exact_hosted_base_and_head_objects() {
    let remote_directory = tempfile::tempdir().expect("remote tempdir");
    let remote = Repository::init_bare(remote_directory.path()).expect("bare remote");
    remote
        .set_head("refs/heads/main")
        .expect("remote default branch");

    let seed_directory = tempfile::tempdir().expect("seed tempdir");
    let seed = Repository::init(seed_directory.path()).expect("seed repository");
    seed.set_head("refs/heads/main").expect("main branch");
    fs::write(seed_directory.path().join("base.txt"), "base\n").expect("base file");
    let base = commit(&seed, "base");
    seed.remote("origin", remote_directory.path().to_string_lossy().as_ref())
        .expect("origin");
    push(&seed, "refs/heads/main:refs/heads/main");

    let base_commit = seed.find_commit(base).expect("base commit");
    seed.branch("feature", &base_commit, false)
        .expect("feature branch");
    drop(base_commit);
    seed.set_head("refs/heads/feature").expect("feature head");
    seed.checkout_head(None).expect("feature checkout");
    fs::write(seed_directory.path().join("feature.txt"), "feature\n").expect("feature file");
    let head = commit(&seed, "feature");
    push(&seed, "refs/heads/feature:refs/pull/7/head");

    let client_directory = tempfile::tempdir().expect("client tempdir");
    Repository::clone(
        remote_directory.path().to_string_lossy().as_ref(),
        client_directory.path(),
    )
    .expect("client clone");
    let client = Repository::open(client_directory.path()).expect("client repository");
    let unrelated_remote = tempfile::tempdir().expect("unrelated remote tempdir");
    Repository::init_bare(unrelated_remote.path()).expect("unrelated bare remote");
    client
        .remote(
            "upstream",
            unrelated_remote.path().to_string_lossy().as_ref(),
        )
        .expect("upstream remote");
    client
        .reference("refs/remotes/upstream/main", base, true, "test upstream")
        .expect("upstream tracking reference");
    client
        .find_branch("main", BranchType::Local)
        .expect("client main")
        .set_upstream(Some("upstream/main"))
        .expect("main tracks upstream");

    seed.set_head("refs/heads/main").expect("return to main");
    seed.checkout_head(None).expect("main checkout");
    fs::write(seed_directory.path().join("base.txt"), "advanced\n").expect("advance base");
    let advanced_base = commit(&seed, "advance base");
    push(&seed, "refs/heads/main:refs/heads/main");

    let range = fetch_hosted_review_range(
        client_directory.path().to_string_lossy().as_ref(),
        "origin",
        "main",
        &head.to_string(),
        Some("refs/pull/7/head"),
    )
    .expect("hosted range");

    assert_eq!(range.base_oid, advanced_base.to_string());
    assert_eq!(range.head_oid, head.to_string());
    assert_eq!(range.retention_id.len(), 32);
    let hosted_refs = client
        .references()
        .expect("client references")
        .filter_map(Result::ok)
        .filter_map(|reference| reference.name().ok().map(str::to_string))
        .filter(|name| name.starts_with("refs/alera/hosted-reviews/"))
        .collect::<Vec<_>>();
    assert_eq!(hosted_refs.len(), 2);
    assert!(hosted_refs.contains(&format!(
        "refs/alera/hosted-reviews/tabs/{}/base",
        range.retention_id
    )));
    assert!(hosted_refs.contains(&format!(
        "refs/alera/hosted-reviews/tabs/{}/head",
        range.retention_id
    )));
    assert!(client.find_commit(head).is_ok());

    release_hosted_review_range(
        client_directory.path().to_string_lossy().as_ref(),
        &range.retention_id,
    )
    .expect("release hosted range");
    let remaining = client
        .references()
        .expect("client references after release")
        .filter_map(Result::ok)
        .filter_map(|reference| reference.name().ok().map(str::to_string))
        .filter(|name| name.starts_with("refs/alera/hosted-reviews/"))
        .count();
    assert_eq!(remaining, 0);
}

fn push(repository: &Repository, refspec: &str) {
    repository
        .find_remote("origin")
        .expect("origin")
        .push(&[refspec], None)
        .expect("push ref");
}

fn commit(repository: &Repository, message: &str) -> Oid {
    let mut index = repository.index().expect("index");
    index
        .add_all(["*"], IndexAddOption::DEFAULT, None)
        .expect("add files");
    index.write().expect("write index");
    let tree = repository
        .find_tree(index.write_tree().expect("tree id"))
        .expect("tree");
    let signature = Signature::now("Alera", "alera@example.com").expect("signature");
    let parent = repository
        .head()
        .ok()
        .and_then(|head| head.target())
        .map(|oid| repository.find_commit(oid).expect("parent"));
    let parents = parent.iter().collect::<Vec<_>>();
    repository
        .commit(
            Some("HEAD"),
            &signature,
            &signature,
            message,
            &tree,
            &parents,
        )
        .expect("commit")
}
