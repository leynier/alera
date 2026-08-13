use std::fs;

use git2::{BranchType, IndexAddOption, Oid, Repository, Signature};

use super::{
    fetch_hosted_review_range, hosted_review_operations, persist_hosted_review_range,
    release_hosted_review_range, sweep_hosted_review_ranges, HostedReviewFetch,
};

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

    let range = fetch_hosted_review_range(HostedReviewFetch {
        repo_path: client_directory.path().to_string_lossy().as_ref(),
        remote_name: "origin",
        base_branch: "main",
        head_sha: &head.to_string(),
        head_remote: None,
        comparison_base_sha: Some(&base.to_string()),
        merge_commit_sha: None,
        review_ref: Some("refs/pull/7/head"),
    })
    .expect("hosted range");

    assert_ne!(advanced_base, base);
    assert_eq!(range.base_oid, base.to_string());
    assert_eq!(range.head_oid, head.to_string());
    assert_eq!(range.retention_id.len(), 32);
    let operations = hosted_review_operations();
    assert!(operations.iter().any(|operation| {
        operation.retention_id == range.retention_id
            && operation.repo_path == client_directory.path().to_string_lossy()
    }));
    let hosted_refs = client
        .references()
        .expect("client references")
        .filter_map(Result::ok)
        .filter_map(|reference| reference.name().ok().map(str::to_string))
        .filter(|name| name.starts_with("refs/alera/hosted-reviews/"))
        .collect::<Vec<_>>();
    assert_eq!(hosted_refs.len(), 2);
    assert!(hosted_refs.contains(&format!(
        "refs/alera/hosted-reviews/operations/{}/base",
        range.retention_id
    )));
    assert!(hosted_refs.contains(&format!(
        "refs/alera/hosted-reviews/operations/{}/head",
        range.retention_id
    )));
    assert!(client.find_commit(head).is_ok());

    persist_hosted_review_range(
        client_directory.path().to_string_lossy().as_ref(),
        &range.retention_id,
    )
    .expect("persist hosted range");
    assert!(!hosted_review_operations()
        .iter()
        .any(|operation| operation.retention_id == range.retention_id));
    assert!(client
        .find_reference(&format!(
            "refs/alera/hosted-reviews/tabs/{}/head",
            range.retention_id
        ))
        .is_ok());

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

#[test]
fn fetches_fork_head_from_its_source_repository() {
    let target_directory = tempfile::tempdir().expect("target tempdir");
    let target = Repository::init_bare(target_directory.path()).expect("target remote");
    target
        .set_head("refs/heads/main")
        .expect("target default branch");
    let fork_directory = tempfile::tempdir().expect("fork tempdir");
    let fork = Repository::init_bare(fork_directory.path()).expect("fork remote");
    fork.set_head("refs/heads/main")
        .expect("fork default branch");

    let seed_directory = tempfile::tempdir().expect("seed tempdir");
    let seed = Repository::init(seed_directory.path()).expect("seed repository");
    seed.set_head("refs/heads/main").expect("main branch");
    fs::write(seed_directory.path().join("base.txt"), "base\n").expect("base file");
    let base = commit(&seed, "base");
    seed.remote("target", target_directory.path().to_string_lossy().as_ref())
        .expect("target remote");
    seed.remote("fork", fork_directory.path().to_string_lossy().as_ref())
        .expect("fork remote");
    seed.find_remote("target")
        .expect("target")
        .push(&["refs/heads/main:refs/heads/main"], None)
        .expect("push target main");

    let base_commit = seed.find_commit(base).expect("base commit");
    seed.branch("feature", &base_commit, false)
        .expect("feature branch");
    drop(base_commit);
    seed.set_head("refs/heads/feature").expect("feature head");
    seed.checkout_head(None).expect("feature checkout");
    fs::write(seed_directory.path().join("feature.txt"), "fork\n").expect("feature file");
    let head = commit(&seed, "fork feature");
    seed.find_remote("fork")
        .expect("fork")
        .push(&["refs/heads/feature:refs/heads/feature"], None)
        .expect("push fork feature");

    let client_directory = tempfile::tempdir().expect("client tempdir");
    Repository::clone(
        target_directory.path().to_string_lossy().as_ref(),
        client_directory.path(),
    )
    .expect("client clone");
    let range = fetch_hosted_review_range(HostedReviewFetch {
        repo_path: client_directory.path().to_string_lossy().as_ref(),
        remote_name: "origin",
        base_branch: "main",
        head_sha: &head.to_string(),
        head_remote: Some(fork_directory.path().to_string_lossy().as_ref()),
        comparison_base_sha: Some(&base.to_string()),
        merge_commit_sha: None,
        review_ref: Some("refs/heads/feature"),
    })
    .expect("fork hosted range");

    assert_eq!(range.base_oid, base.to_string());
    assert_eq!(range.head_oid, head.to_string());
}

#[test]
fn derives_the_pre_merge_base_when_the_target_contains_the_review_head() {
    let remote_directory = tempfile::tempdir().expect("remote tempdir");
    let remote = Repository::init_bare(remote_directory.path()).expect("bare remote");
    remote.set_head("refs/heads/main").expect("remote head");

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
        .expect("feature");
    drop(base_commit);
    seed.set_head("refs/heads/feature").expect("feature head");
    seed.checkout_head(None).expect("feature checkout");
    fs::write(seed_directory.path().join("feature.txt"), "feature\n").expect("feature file");
    let head = commit(&seed, "feature");
    push(&seed, "refs/heads/feature:refs/pull/8/head");

    seed.set_head("refs/heads/main").expect("return to main");
    seed.checkout_head(None).expect("main checkout");
    fs::write(seed_directory.path().join("base.txt"), "advanced\n").expect("advance base");
    let pre_merge_base = commit(&seed, "advance base");
    let merge = merge_commit(&seed, pre_merge_base, head, "merge review");
    push(&seed, "refs/heads/main:refs/heads/main");

    let client_directory = tempfile::tempdir().expect("client tempdir");
    Repository::clone(
        remote_directory.path().to_string_lossy().as_ref(),
        client_directory.path(),
    )
    .expect("client clone");
    let range = fetch_hosted_review_range(HostedReviewFetch {
        repo_path: client_directory.path().to_string_lossy().as_ref(),
        remote_name: "origin",
        base_branch: "main",
        head_sha: &head.to_string(),
        head_remote: None,
        comparison_base_sha: None,
        merge_commit_sha: Some(&merge.to_string()),
        review_ref: Some("refs/pull/8/head"),
    })
    .expect("merged hosted range");

    assert_eq!(range.base_oid, pre_merge_base.to_string());
    assert_ne!(range.base_oid, range.head_oid);
    release_hosted_review_range(
        client_directory.path().to_string_lossy().as_ref(),
        &range.retention_id,
    )
    .expect("release merged hosted range");
}

#[test]
fn unshallows_when_the_review_merge_base_is_outside_the_boundary() {
    let remote_directory = tempfile::tempdir().expect("remote tempdir");
    let remote = Repository::init_bare(remote_directory.path()).expect("bare remote");
    remote.set_head("refs/heads/main").expect("remote head");

    let seed_directory = tempfile::tempdir().expect("seed tempdir");
    let seed = Repository::init(seed_directory.path()).expect("seed repository");
    seed.set_head("refs/heads/main").expect("main branch");
    seed.remote("origin", remote_directory.path().to_string_lossy().as_ref())
        .expect("origin");
    let mut branch_point = None;
    for index in 1..=5 {
        fs::write(seed_directory.path().join("base.txt"), format!("{index}\n")).expect("base file");
        let oid = commit(&seed, &format!("base {index}"));
        if index == 2 {
            branch_point = Some(oid);
        }
    }
    push(&seed, "refs/heads/main:refs/heads/main");
    let branch_point = branch_point.expect("branch point");
    let branch_commit = seed.find_commit(branch_point).expect("branch commit");
    seed.branch("feature", &branch_commit, false)
        .expect("feature");
    drop(branch_commit);
    seed.set_head("refs/heads/feature").expect("feature head");
    seed.checkout_head(None).expect("feature checkout");
    fs::write(seed_directory.path().join("feature.txt"), "feature\n").expect("feature file");
    let head = commit(&seed, "feature");
    push(&seed, "refs/heads/feature:refs/pull/9/head");

    let client_directory = tempfile::tempdir().expect("client tempdir");
    let remote_url = format!("file://{}", remote_directory.path().to_string_lossy());
    let client = Repository::clone(&remote_url, client_directory.path()).expect("client clone");
    let current_main = client
        .refname_to_id("refs/heads/main")
        .expect("current main");
    fs::write(client.path().join("shallow"), format!("{current_main}\n"))
        .expect("shallow boundary");
    drop(client);
    let client = Repository::open(client_directory.path()).expect("shallow client");
    assert!(client.is_shallow());
    drop(client);

    let range = fetch_hosted_review_range(HostedReviewFetch {
        repo_path: client_directory.path().to_string_lossy().as_ref(),
        remote_name: "origin",
        base_branch: "main",
        head_sha: &head.to_string(),
        head_remote: None,
        comparison_base_sha: None,
        merge_commit_sha: None,
        review_ref: Some("refs/pull/9/head"),
    })
    .expect("shallow hosted range");
    let refreshed = Repository::open(client_directory.path()).expect("refreshed client");

    assert!(!refreshed.is_shallow());
    assert_eq!(
        refreshed
            .merge_base(
                Oid::from_str(&range.base_oid).expect("base oid"),
                Oid::from_str(&range.head_oid).expect("head oid"),
            )
            .expect("merge base"),
        branch_point,
    );
    release_hosted_review_range(
        client_directory.path().to_string_lossy().as_ref(),
        &range.retention_id,
    )
    .expect("release shallow hosted range");
}

#[test]
fn sweeps_unowned_hosted_review_refs() {
    let directory = tempfile::tempdir().expect("tempdir");
    let repository = Repository::init(directory.path()).expect("repository");
    let object = repository.blob(b"review").expect("object");
    let retained = "00000000000000000000000000000001";
    let stale = "00000000000000000000000000000002";
    for (namespace, retention_id) in [("tabs", retained), ("tabs", stale), ("operations", stale)] {
        for role in ["base", "head"] {
            repository
                .reference(
                    &format!("refs/alera/hosted-reviews/{namespace}/{retention_id}/{role}"),
                    object,
                    true,
                    "test",
                )
                .expect("hosted ref");
        }
    }

    sweep_hosted_review_ranges(
        directory.path().to_string_lossy().as_ref(),
        &[retained.into()],
    )
    .expect("sweep");

    assert!(repository
        .find_reference(&format!("refs/alera/hosted-reviews/tabs/{retained}/head"))
        .is_ok());
    assert!(repository
        .find_reference(&format!("refs/alera/hosted-reviews/tabs/{stale}/head"))
        .is_err());
    assert!(repository
        .find_reference(&format!(
            "refs/alera/hosted-reviews/operations/{stale}/head"
        ))
        .is_err());
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

fn merge_commit(repository: &Repository, base: Oid, head: Oid, message: &str) -> Oid {
    let signature = Signature::now("Alera", "alera@example.com").expect("signature");
    let base = repository.find_commit(base).expect("base parent");
    let head = repository.find_commit(head).expect("head parent");
    let tree = head.tree().expect("head tree");
    repository
        .commit(
            Some("refs/heads/main"),
            &signature,
            &signature,
            message,
            &tree,
            &[&base, &head],
        )
        .expect("merge commit")
}
