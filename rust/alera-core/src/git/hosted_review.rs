use std::collections::HashSet;

use git2::{Branch, Oid, Reference, Repository};
use uuid::Uuid;

use super::{git_cli_in_path, open_repo, GitError, GitErrorKind};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GitHostedReviewRange {
    pub base_oid: String,
    pub head_oid: String,
    pub retention_id: String,
}

pub fn fetch_hosted_review_range(
    repo_path: &str,
    remote_name: &str,
    base_branch: &str,
    head_sha: &str,
    comparison_base_sha: Option<&str>,
    merge_commit_sha: Option<&str>,
    review_ref: Option<&str>,
) -> Result<GitHostedReviewRange, GitError> {
    let repo = open_repo(repo_path)?;
    repo.find_remote(remote_name).map_err(|_| {
        GitError::new(
            GitErrorKind::RemoteNotFound,
            format!("hosted review remote not found: {remote_name}"),
        )
    })?;
    if !Branch::name_is_valid(base_branch).map_err(GitError::from_git2)? {
        return Err(GitError::new(GitErrorKind::InvalidBranchName, base_branch));
    }
    validate_hosted_sha(head_sha, "head")?;
    if let Some(value) = comparison_base_sha {
        validate_hosted_sha(value, "comparison base")?;
    }
    if let Some(value) = merge_commit_sha {
        validate_hosted_sha(value, "merge commit")?;
    }
    if review_ref.is_some_and(|value| !Reference::is_valid_name(value)) {
        return Err(GitError::new(
            GitErrorKind::InvalidBranchName,
            "invalid hosted review ref",
        ));
    }
    let retention_id = Uuid::new_v4().simple().to_string();
    let base_source = format!("refs/heads/{base_branch}");
    let base_target = format!("refs/alera/hosted-reviews/operations/{retention_id}/base");
    let head_target = format!("refs/alera/hosted-reviews/operations/{retention_id}/head");
    let candidate_target = format!("refs/alera/hosted-reviews/operations/{retention_id}/candidate");
    let result = (|| {
        fetch_ref(repo_path, remote_name, &base_source, &base_target)?;

        let primary_head = review_ref.unwrap_or(head_sha);
        let head_source = if let Err(primary_error) =
            fetch_ref(repo_path, remote_name, primary_head, &head_target)
        {
            if review_ref.is_none()
                || fetch_ref(repo_path, remote_name, head_sha, &head_target).is_err()
            {
                return Err(primary_error);
            }
            head_sha
        } else {
            primary_head
        };

        let candidate_source = comparison_base_sha.or(merge_commit_sha);
        if let Some(source) = candidate_source {
            let _ = fetch_ref(repo_path, remote_name, source, &candidate_target);
        }

        if !hosted_range_is_connected(
            repo_path,
            &base_target,
            &head_target,
            comparison_base_sha,
            merge_commit_sha,
        )? {
            let shallow = open_repo(repo_path)?.is_shallow();
            if shallow {
                fetch_review_history(
                    repo_path,
                    remote_name,
                    &base_source,
                    &base_target,
                    head_source,
                    &head_target,
                )?;
                if let Some(source) = candidate_source {
                    let _ = fetch_ref(repo_path, remote_name, source, &candidate_target);
                }
            }
        }

        let refreshed = open_repo(repo_path)?;
        let head_oid = refreshed
            .refname_to_id(&head_target)
            .map_err(GitError::from_git2)?;
        if head_oid.to_string() != head_sha.to_ascii_lowercase() {
            return Err(GitError::new(
                GitErrorKind::Conflict,
                "the hosted review changed while its diff was opening",
            ));
        }
        let base_oid = comparison_base_oid(
            &refreshed,
            &base_target,
            head_oid,
            comparison_base_sha,
            merge_commit_sha,
        )?;
        refreshed
            .merge_base(base_oid, head_oid)
            .map_err(GitError::from_git2)?;
        refreshed
            .reference(
                &base_target,
                base_oid,
                true,
                "alera: freeze hosted review comparison base",
            )
            .map_err(GitError::from_git2)?;
        if let Ok(mut reference) = refreshed.find_reference(&candidate_target) {
            reference.delete().map_err(GitError::from_git2)?;
        }
        Ok(GitHostedReviewRange {
            base_oid: base_oid.to_string(),
            head_oid: head_oid.to_string(),
            retention_id: retention_id.clone(),
        })
    })();
    if result.is_err() {
        cleanup_temporary_refs(repo_path, [&base_target, &head_target, &candidate_target]);
    }
    result
}

fn validate_hosted_sha(value: &str, role: &str) -> Result<(), GitError> {
    if matches!(value.len(), 40 | 64) && value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Ok(());
    }
    Err(GitError::new(
        GitErrorKind::Internal,
        format!("invalid hosted {role} SHA"),
    ))
}

fn hosted_range_is_connected(
    repo_path: &str,
    base_target: &str,
    head_target: &str,
    comparison_base_sha: Option<&str>,
    merge_commit_sha: Option<&str>,
) -> Result<bool, GitError> {
    let repo = open_repo(repo_path)?;
    let Ok(head_oid) = repo.refname_to_id(head_target) else {
        return Ok(false);
    };
    let Ok(base_oid) = comparison_base_oid(
        &repo,
        base_target,
        head_oid,
        comparison_base_sha,
        merge_commit_sha,
    ) else {
        return Ok(false);
    };
    Ok(repo.merge_base(base_oid, head_oid).is_ok())
}

fn comparison_base_oid(
    repo: &Repository,
    base_target: &str,
    head_oid: Oid,
    comparison_base_sha: Option<&str>,
    merge_commit_sha: Option<&str>,
) -> Result<Oid, GitError> {
    if let Some(value) = comparison_base_sha {
        return Oid::from_str(value)
            .and_then(|oid| repo.find_commit(oid).map(|commit| commit.id()))
            .map_err(GitError::from_git2);
    }
    let current_base = repo
        .refname_to_id(base_target)
        .map_err(GitError::from_git2)?;
    if let Some(value) = merge_commit_sha {
        let contains_head = current_base == head_oid
            || repo
                .graph_descendant_of(current_base, head_oid)
                .map_err(GitError::from_git2)?;
        if contains_head {
            return Oid::from_str(value)
                .and_then(|oid| repo.find_commit(oid))
                .and_then(|commit| commit.parent_id(0))
                .map_err(GitError::from_git2);
        }
    }
    Ok(current_base)
}

fn fetch_ref(path: &str, remote: &str, source: &str, target: &str) -> Result<(), GitError> {
    let refspec = format!("+{source}:{target}");
    git_cli_in_path(
        path,
        &[
            "fetch",
            "--no-tags",
            "--no-write-fetch-head",
            remote,
            &refspec,
        ],
    )
}

fn fetch_review_history(
    path: &str,
    remote: &str,
    base_source: &str,
    base_target: &str,
    head_source: &str,
    head_target: &str,
) -> Result<(), GitError> {
    let base_refspec = format!("+{base_source}:{base_target}");
    let head_refspec = format!("+{head_source}:{head_target}");
    git_cli_in_path(
        path,
        &[
            "fetch",
            "--unshallow",
            "--no-tags",
            "--no-write-fetch-head",
            remote,
            &base_refspec,
            &head_refspec,
        ],
    )
}

pub fn release_hosted_review_range(repo_path: &str, retention_id: &str) -> Result<(), GitError> {
    validate_retention_id(retention_id)?;
    let repo = open_repo(repo_path)?;
    for namespace in ["tabs", "operations"] {
        for role in ["base", "head"] {
            let name = hosted_ref_name(namespace, retention_id, role);
            if let Ok(mut reference) = repo.find_reference(&name) {
                reference.delete().map_err(GitError::from_git2)?;
            }
        }
    }
    Ok(())
}

pub fn persist_hosted_review_range(repo_path: &str, retention_id: &str) -> Result<(), GitError> {
    validate_retention_id(retention_id)?;
    let repo = open_repo(repo_path)?;
    for role in ["base", "head"] {
        let name = retained_ref_name(retention_id, role);
        if repo.find_reference(&name).is_err() {
            let operation = operation_ref_name(retention_id, role);
            let object_id = repo
                .refname_to_id(&operation)
                .map_err(GitError::from_git2)?;
            repo.reference(
                &name,
                object_id,
                true,
                "alera: retain object for a persisted hosted review tab",
            )
            .map_err(GitError::from_git2)?;
        }
    }
    for role in ["base", "head"] {
        if let Ok(mut reference) = repo.find_reference(&operation_ref_name(retention_id, role)) {
            reference.delete().map_err(GitError::from_git2)?;
        }
    }
    Ok(())
}

pub fn sweep_hosted_review_ranges(
    repo_path: &str,
    retained_ids: &[String],
) -> Result<(), GitError> {
    let repo = open_repo(repo_path)?;
    let retained = retained_ids
        .iter()
        .map(String::as_str)
        .collect::<HashSet<_>>();
    let mut stale_names = Vec::<String>::new();
    for namespace in ["operations", "tabs"] {
        let pattern = format!("refs/alera/hosted-reviews/{namespace}/*/*");
        let references = repo
            .references_glob(&pattern)
            .map_err(GitError::from_git2)?;
        for reference in references.filter_map(Result::ok) {
            let Ok(name) = reference.name() else {
                continue;
            };
            let retention_id = name.rsplit('/').nth(1).unwrap_or_default();
            if namespace == "operations" || !retained.contains(retention_id) {
                stale_names.push(name.to_string());
            }
        }
    }
    for name in stale_names {
        if let Ok(mut reference) = repo.find_reference(&name) {
            reference.delete().map_err(GitError::from_git2)?;
        }
    }
    Ok(())
}

fn validate_retention_id(retention_id: &str) -> Result<(), GitError> {
    if retention_id.len() == 32
        && retention_id
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase())
    {
        return Ok(());
    }
    Err(GitError::new(
        GitErrorKind::Internal,
        "invalid hosted review retention id",
    ))
}

fn retained_ref_name(retention_id: &str, role: &str) -> String {
    hosted_ref_name("tabs", retention_id, role)
}

fn operation_ref_name(retention_id: &str, role: &str) -> String {
    hosted_ref_name("operations", retention_id, role)
}

fn hosted_ref_name(namespace: &str, retention_id: &str, role: &str) -> String {
    format!("refs/alera/hosted-reviews/{namespace}/{retention_id}/{role}")
}

fn cleanup_temporary_refs<const N: usize>(path: &str, names: [&str; N]) {
    let Ok(repo) = open_repo(path) else {
        return;
    };
    for name in names {
        if let Ok(mut reference) = repo.find_reference(name) {
            let _ = reference.delete();
        }
    }
}

#[cfg(test)]
#[path = "../git_hosted_review_tests.rs"]
mod tests;
