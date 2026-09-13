use std::collections::{HashMap, HashSet, VecDeque};
use std::path::Path;

use git2::{BranchType, ErrorCode, Oid, Repository, Sort};

use super::git_diff_paths::GitPathContext;
use super::{
    current_head_commit, head_branch_name, open_repo, GitError, GitHistoryItem, GitHistoryItemRef,
    GitHistoryRefCategory, GitHistoryResult,
};

const DEFAULT_HISTORY_LIMIT: u32 = 50;
const MAX_HISTORY_LIMIT: u32 = 200;

pub(super) fn git_history(
    path: String,
    limit: Option<u32>,
    base_ref: Option<String>,
) -> Result<GitHistoryResult, GitError> {
    let repo = open_repo(&path)?;
    let paths = GitPathContext::new(&repo, &path)?;
    let limit = limit
        .unwrap_or(DEFAULT_HISTORY_LIMIT)
        .clamp(1, MAX_HISTORY_LIMIT);
    let Some(head) = current_head_commit(&repo)? else {
        return Ok(GitHistoryResult {
            items: Vec::new(),
            current_ref: None,
            remote_ref: None,
            base_ref: None,
            merge_base: None,
            has_incoming_changes: false,
            has_outgoing_changes: false,
            has_more: false,
            limit,
        });
    };
    let head_oid = head.id();
    let branch_name = head_branch_name(&repo);
    let current_ref = resolve_current_ref(&repo, &branch_name, head_oid)?;
    let remote_ref = resolve_upstream_ref(&repo, &branch_name)?;
    let remote_oid = remote_ref
        .as_ref()
        .and_then(|remote| remote.revision.as_deref())
        .and_then(|value| Oid::from_str(value).ok());
    let base_ref = resolve_named_ref(&repo, base_ref.as_deref())?.filter(|base| {
        base.id != current_ref.id
            && remote_ref
                .as_ref()
                .is_none_or(|remote| remote.id != base.id)
    });
    let merge_base_oid = if let Some(remote_oid) = remote_oid {
        if remote_oid != head_oid {
            repo.merge_base(head_oid, remote_oid).ok()
        } else {
            None
        }
    } else {
        None
    };
    let refs_by_oid = refs_by_oid(&repo)?;
    let mut revwalk = repo.revwalk().map_err(GitError::from_git2)?;
    revwalk.push(head_oid).map_err(GitError::from_git2)?;
    if let Some(remote_oid) = remote_oid.filter(|remote_oid| *remote_oid != head_oid) {
        revwalk.push(remote_oid).map_err(GitError::from_git2)?;
    }
    revwalk
        .set_sorting(Sort::TOPOLOGICAL | Sort::TIME)
        .map_err(GitError::from_git2)?;
    let mut parsed = Vec::new();
    for oid in revwalk {
        let oid = oid.map_err(GitError::from_git2)?;
        let commit = repo.find_commit(oid).map_err(GitError::from_git2)?;
        if !commit_touches_workspace(&repo, &paths, &commit)? {
            continue;
        }
        parsed.push(history_item_from_commit(&commit, refs_by_oid.get(&oid)));
        if parsed.len() > limit as usize {
            break;
        }
    }
    let has_more = parsed.len() > limit as usize;
    parsed.truncate(limit as usize);
    let visible_ids = parsed
        .iter()
        .filter_map(|item| Oid::from_str(&item.id).ok())
        .collect::<HashSet<_>>();
    let scoped_merge_base_oid = if paths.is_workspace_root() {
        merge_base_oid
    } else {
        merge_base_oid
            .map(|oid| scoped_visible_ancestor_oids(&repo, &visible_ids, oid))
            .transpose()?
            .and_then(|ancestors| ancestors.into_iter().next())
    };
    let merge_base = scoped_merge_base_oid.map(|oid| oid.to_string());
    if !paths.is_workspace_root() {
        rewrite_history_parents_to_visible_ancestors(&repo, &visible_ids, &mut parsed)?;
    }
    let has_incoming_changes =
        if let (Some(remote_oid), Some(merge_base_oid)) = (remote_oid, merge_base_oid) {
            remote_oid != merge_base_oid
                && range_has_workspace_changes(&repo, &paths, merge_base_oid, remote_oid)?
        } else {
            false
        };
    let has_outgoing_changes =
        if let (Some(remote_oid), Some(merge_base_oid)) = (remote_oid, merge_base_oid) {
            remote_oid != head_oid
                && head_oid != merge_base_oid
                && range_has_workspace_changes(&repo, &paths, merge_base_oid, head_oid)?
        } else {
            false
        };

    Ok(GitHistoryResult {
        items: parsed,
        current_ref: Some(current_ref),
        remote_ref,
        base_ref,
        merge_base,
        has_incoming_changes,
        has_outgoing_changes,
        has_more,
        limit,
    })
}

fn resolve_current_ref(
    repo: &Repository,
    branch_name: &str,
    head_oid: Oid,
) -> Result<GitHistoryItemRef, GitError> {
    if branch_name != "HEAD" {
        return Ok(GitHistoryItemRef {
            id: format!("refs/heads/{branch_name}"),
            name: branch_name.to_string(),
            revision: Some(head_oid.to_string()),
            category: Some(GitHistoryRefCategory::Branches),
        });
    }
    let _ = repo;
    Ok(GitHistoryItemRef {
        id: head_oid.to_string(),
        name: short_oid(head_oid),
        revision: Some(head_oid.to_string()),
        category: Some(GitHistoryRefCategory::Commits),
    })
}

fn resolve_upstream_ref(
    repo: &Repository,
    branch_name: &str,
) -> Result<Option<GitHistoryItemRef>, GitError> {
    if branch_name == "HEAD" {
        return Ok(None);
    }
    let Ok(local) = repo.find_branch(branch_name, BranchType::Local) else {
        return Ok(None);
    };
    let Ok(upstream) = local.upstream() else {
        return Ok(None);
    };
    let Some(oid) = upstream.get().target() else {
        return Ok(None);
    };
    let full_name = upstream.get().name().unwrap_or_default();
    Ok(Some(history_ref_from_full_name(
        full_name,
        upstream
            .name()
            .map_err(GitError::from_git2)?
            .unwrap_or(full_name),
        oid,
    )))
}

fn resolve_named_ref(
    repo: &Repository,
    name: Option<&str>,
) -> Result<Option<GitHistoryItemRef>, GitError> {
    let Some(name) = name.map(str::trim).filter(|name| !name.is_empty()) else {
        return Ok(None);
    };
    if name.starts_with('-') {
        return Ok(None);
    }
    let object = match repo.revparse_single(name) {
        Ok(object) => object,
        Err(error)
            if matches!(
                error.code(),
                ErrorCode::NotFound | ErrorCode::Ambiguous | ErrorCode::InvalidSpec
            ) =>
        {
            return Ok(None);
        }
        Err(error) => return Err(GitError::from_git2(error)),
    };
    let commit = match object.peel_to_commit() {
        Ok(commit) => commit,
        Err(_) => return Ok(None),
    };
    let full_name = repo
        .find_reference(name)
        .ok()
        .and_then(|reference| reference.name().ok().map(ToString::to_string));
    Ok(Some(history_ref_from_full_name(
        full_name.as_deref().unwrap_or(name),
        name,
        commit.id(),
    )))
}

fn refs_by_oid(repo: &Repository) -> Result<HashMap<Oid, Vec<GitHistoryItemRef>>, GitError> {
    let mut output: HashMap<Oid, Vec<GitHistoryItemRef>> = HashMap::new();
    let references = repo.references().map_err(GitError::from_git2)?;
    for reference in references {
        let reference = reference.map_err(GitError::from_git2)?;
        let Ok(full_name) = reference.name() else {
            continue;
        };
        if full_name == "HEAD" || full_name.ends_with("/HEAD") {
            continue;
        }
        let category = category_for_ref(full_name);
        if category.is_none() {
            continue;
        }
        let oid = if category == Some(GitHistoryRefCategory::Tags) {
            reference
                .peel_to_commit()
                .ok()
                .map(|commit| commit.id())
                .or_else(|| reference.target())
        } else {
            reference
                .target()
                .or_else(|| reference.peel_to_commit().ok().map(|commit| commit.id()))
        };
        let Some(oid) = oid else {
            continue;
        };
        output
            .entry(oid)
            .or_default()
            .push(history_ref_from_full_name(
                full_name,
                short_name_for_ref(full_name),
                oid,
            ));
    }
    for refs in output.values_mut() {
        refs.sort_by(compare_refs);
    }
    Ok(output)
}

fn commit_touches_workspace(
    repo: &Repository,
    paths: &GitPathContext,
    commit: &git2::Commit<'_>,
) -> Result<bool, GitError> {
    if paths.is_workspace_root() {
        return Ok(true);
    }
    let commit_tree = commit.tree().map_err(GitError::from_git2)?;
    let parent_tree = commit
        .parent_id(0)
        .ok()
        .map(|oid| {
            repo.find_commit(oid)
                .and_then(|commit| commit.tree())
                .map_err(GitError::from_git2)
        })
        .transpose()?;
    let diff = repo
        .diff_tree_to_tree(parent_tree.as_ref(), Some(&commit_tree), None)
        .map_err(GitError::from_git2)?;
    for delta in diff.deltas() {
        let new_path = delta.new_file().path().map(repo_path_string);
        let old_path = delta.old_file().path().map(repo_path_string);
        if new_path
            .as_deref()
            .is_some_and(|path| paths.to_workspace_path(path).is_some())
            || old_path
                .as_deref()
                .is_some_and(|path| paths.to_workspace_path(path).is_some())
        {
            return Ok(true);
        }
    }
    Ok(false)
}

fn range_has_workspace_changes(
    repo: &Repository,
    paths: &GitPathContext,
    base_oid: Oid,
    tip_oid: Oid,
) -> Result<bool, GitError> {
    if tip_oid == base_oid {
        return Ok(false);
    }
    if paths.is_workspace_root() {
        return Ok(true);
    }
    let mut revwalk = repo.revwalk().map_err(GitError::from_git2)?;
    revwalk.push(tip_oid).map_err(GitError::from_git2)?;
    revwalk.hide(base_oid).map_err(GitError::from_git2)?;
    for oid in revwalk {
        let oid = oid.map_err(GitError::from_git2)?;
        let commit = repo.find_commit(oid).map_err(GitError::from_git2)?;
        if commit_touches_workspace(repo, paths, &commit)? {
            return Ok(true);
        }
    }
    Ok(false)
}

fn rewrite_history_parents_to_visible_ancestors(
    repo: &Repository,
    visible_ids: &HashSet<Oid>,
    items: &mut [GitHistoryItem],
) -> Result<(), GitError> {
    for item in items {
        let mut seen = HashSet::new();
        let mut parent_ids = Vec::new();
        for parent_id in &item.parent_ids {
            let Ok(parent_oid) = Oid::from_str(parent_id) else {
                continue;
            };
            for ancestor_oid in scoped_visible_ancestor_oids(repo, visible_ids, parent_oid)? {
                if seen.insert(ancestor_oid) {
                    parent_ids.push(ancestor_oid.to_string());
                }
            }
        }
        item.parent_ids = parent_ids;
    }
    Ok(())
}

fn scoped_visible_ancestor_oids(
    repo: &Repository,
    visible_ids: &HashSet<Oid>,
    start_oid: Oid,
) -> Result<Vec<Oid>, GitError> {
    if visible_ids.contains(&start_oid) {
        return Ok(vec![start_oid]);
    }
    let mut output = Vec::new();
    let mut seen = HashSet::from([start_oid]);
    let mut queue = VecDeque::from([start_oid]);
    while let Some(oid) = queue.pop_front() {
        let commit = repo.find_commit(oid).map_err(GitError::from_git2)?;
        for parent_oid in commit.parent_ids() {
            if !seen.insert(parent_oid) {
                continue;
            }
            if visible_ids.contains(&parent_oid) {
                output.push(parent_oid);
            } else {
                queue.push_back(parent_oid);
            }
        }
    }
    Ok(output)
}

fn history_item_from_commit(
    commit: &git2::Commit<'_>,
    references: Option<&Vec<GitHistoryItemRef>>,
) -> GitHistoryItem {
    let message = commit.message().unwrap_or_default().trim_end().to_string();
    let subject = message
        .lines()
        .next()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .unwrap_or("(no commit message)")
        .to_string();
    GitHistoryItem {
        id: commit.id().to_string(),
        parent_ids: commit.parent_ids().map(|oid| oid.to_string()).collect(),
        subject,
        message,
        display_id: Some(short_oid(commit.id())),
        author: commit.author().name().ok().map(ToString::to_string),
        author_email: commit.author().email().ok().map(ToString::to_string),
        timestamp: Some(commit.author().when().seconds().saturating_mul(1000)),
        references: references.cloned().unwrap_or_default(),
    }
}

fn history_ref_from_full_name(full_name: &str, fallback_name: &str, oid: Oid) -> GitHistoryItemRef {
    let category = category_for_ref(full_name).unwrap_or(GitHistoryRefCategory::Commits);
    GitHistoryItemRef {
        id: full_name.to_string(),
        name: short_name_for_ref(full_name)
            .strip_prefix("tag: ")
            .unwrap_or_else(|| short_name_for_ref(fallback_name))
            .to_string(),
        revision: Some(oid.to_string()),
        category: Some(category),
    }
}

fn category_for_ref(full_name: &str) -> Option<GitHistoryRefCategory> {
    if full_name.starts_with("refs/heads/") {
        Some(GitHistoryRefCategory::Branches)
    } else if full_name.starts_with("refs/remotes/") {
        Some(GitHistoryRefCategory::RemoteBranches)
    } else if full_name.starts_with("refs/tags/") {
        Some(GitHistoryRefCategory::Tags)
    } else {
        None
    }
}

fn short_name_for_ref(full_name: &str) -> &str {
    full_name
        .strip_prefix("refs/heads/")
        .or_else(|| full_name.strip_prefix("refs/remotes/"))
        .or_else(|| full_name.strip_prefix("refs/tags/"))
        .unwrap_or(full_name)
}

fn compare_refs(a: &GitHistoryItemRef, b: &GitHistoryItemRef) -> std::cmp::Ordering {
    ref_order(a)
        .cmp(&ref_order(b))
        .then_with(|| a.name.cmp(&b.name))
}

fn ref_order(reference: &GitHistoryItemRef) -> u8 {
    match reference.category {
        Some(GitHistoryRefCategory::Branches) => 1,
        Some(GitHistoryRefCategory::RemoteBranches) => 2,
        Some(GitHistoryRefCategory::Tags) => 3,
        _ => 99,
    }
}

fn short_oid(oid: Oid) -> String {
    oid.to_string().chars().take(7).collect()
}

fn repo_path_string(path: &Path) -> String {
    path.components()
        .filter_map(|component| {
            let text = component.as_os_str().to_string_lossy();
            if text.is_empty() {
                None
            } else {
                Some(text.to_string())
            }
        })
        .collect::<Vec<_>>()
        .join("/")
}
