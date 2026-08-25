//! Expands a project's `.worktreeinclude` into copy rules for a new worktree.
//!
//! The file uses `.gitignore` syntax, matching Conductor and Claude Code:
//! only gitignored files are eligible, tracked files are left alone, and
//! untracked files that Git does not ignore are not copied. Explicit
//! `worktree.copy` rules from `alera.toml` or the Settings UI still run and
//! win when they name the same source path.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

use alera_core::runtime::WorktreeCopyRule;
use anyhow::{Context, Result};
use git2::{Index, Repository, Status, StatusOptions};
use ignore::gitignore::{Gitignore, GitignoreBuilder};

use crate::project_config_toml::normalize_config_path;

pub(crate) const WORKTREE_INCLUDE_FILE: &str = ".worktreeinclude";

pub(crate) fn has_worktree_include(project_root: &Path) -> bool {
    project_root.join(WORKTREE_INCLUDE_FILE).is_file()
}

pub(crate) fn expand_worktree_include(project_root: &Path) -> Result<Vec<WorktreeCopyRule>> {
    let include_path = project_root.join(WORKTREE_INCLUDE_FILE);
    if !include_path.is_file() {
        return Ok(Vec::new());
    }
    let contents = std::fs::read_to_string(&include_path)
        .with_context(|| format!("Could not load {}", include_path.display()))?;
    let matcher = build_matcher(project_root, &include_path, &contents)?;
    let plan = SearchPlan::from_contents(&contents);
    let repository = Repository::open(project_root).with_context(|| {
        format!(
            "Could not open the Git repository at {}",
            project_root.display()
        )
    })?;
    let Some(workdir) = repository.workdir() else {
        anyhow::bail!("{WORKTREE_INCLUDE_FILE} requires a work tree");
    };
    let workdir = std::fs::canonicalize(workdir)?;
    let index = repository.index()?;
    let mut files = BTreeSet::new();
    collect_ignored_matches(&repository, &workdir, &index, &matcher, &plan, &mut files)?;
    let mut rules = Vec::with_capacity(files.len());
    for relative in files {
        let from = match normalize_config_path(&relative, WORKTREE_INCLUDE_FILE) {
            Ok(from) => from,
            Err(_) => continue,
        };
        rules.push(WorktreeCopyRule {
            from,
            to: None,
            overwrite: false,
        });
    }
    Ok(rules)
}

fn build_matcher(project_root: &Path, include_path: &Path, contents: &str) -> Result<Gitignore> {
    let mut builder = GitignoreBuilder::new(project_root);
    for line in contents.lines() {
        builder
            .add_line(Some(include_path.to_path_buf()), line)
            .with_context(|| format!("Invalid {WORKTREE_INCLUDE_FILE} pattern: {line}"))?;
    }
    builder.build().context("Could not parse .worktreeinclude")
}

fn collect_ignored_matches(
    repository: &Repository,
    workdir: &Path,
    index: &Index,
    matcher: &Gitignore,
    plan: &SearchPlan,
    files: &mut BTreeSet<String>,
) -> Result<()> {
    let mut options = StatusOptions::new();
    options
        .include_ignored(true)
        .include_untracked(true)
        .recurse_untracked_dirs(true)
        .exclude_submodules(true);
    let statuses = repository.statuses(Some(&mut options))?;
    for entry in statuses.iter() {
        if !entry.status().contains(Status::IGNORED) {
            continue;
        }
        let Ok(path) = entry.path() else {
            continue;
        };
        let relative = normalize_relative(path);
        if relative.is_empty() || relative.split('/').any(|part| part == ".git") {
            continue;
        }
        if is_tracked(index, &relative) {
            continue;
        }
        let absolute = join_relative(workdir, &relative);
        let metadata = match std::fs::symlink_metadata(&absolute) {
            Ok(metadata) => metadata,
            Err(_) => continue,
        };
        if metadata.file_type().is_symlink() {
            continue;
        }
        if metadata.is_file() {
            if is_selected(matcher, Path::new(&relative), false) {
                files.insert(relative);
            }
            continue;
        }
        if metadata.is_dir() {
            for walk_root in plan.walk_roots(&relative, matcher) {
                collect_matching_files(workdir, &walk_root, index, matcher, files);
            }
        }
    }
    Ok(())
}

fn collect_matching_files(
    workdir: &Path,
    relative_dir: &str,
    index: &Index,
    matcher: &Gitignore,
    files: &mut BTreeSet<String>,
) {
    let directory = join_relative(workdir, relative_dir);
    let Ok(entries) = std::fs::read_dir(&directory) else {
        return;
    };
    for entry in entries.flatten() {
        let name = entry.file_name();
        if name == ".git" {
            continue;
        }
        let child_name = name.to_string_lossy();
        if child_name == ".." || child_name == "." {
            continue;
        }
        let child_relative = if relative_dir.is_empty() {
            child_name.replace('\\', "/")
        } else {
            format!("{relative_dir}/{child_name}")
        };
        let child_path = entry.path();
        let Ok(metadata) = std::fs::symlink_metadata(&child_path) else {
            continue;
        };
        if metadata.file_type().is_symlink() {
            continue;
        }
        if metadata.is_dir() {
            collect_matching_files(workdir, &child_relative, index, matcher, files);
            continue;
        }
        if !metadata.is_file() || is_tracked(index, &child_relative) {
            continue;
        }
        if is_selected(matcher, Path::new(&child_relative), false) {
            files.insert(child_relative);
        }
    }
}

fn is_selected(matcher: &Gitignore, relative: &Path, is_dir: bool) -> bool {
    let direct = matcher.matched(relative, is_dir);
    if !direct.is_none() {
        return direct.is_ignore();
    }
    matcher
        .matched_path_or_any_parents(relative, is_dir)
        .is_ignore()
}

fn is_tracked(index: &Index, relative: &str) -> bool {
    index.get_path(Path::new(relative), 0).is_some()
}

fn normalize_relative(path: &str) -> String {
    path.replace('\\', "/")
        .trim_matches('/')
        .split('/')
        .filter(|part| !part.is_empty() && *part != ".")
        .collect::<Vec<_>>()
        .join("/")
}

fn join_relative(root: &Path, relative: &str) -> PathBuf {
    relative
        .split('/')
        .filter(|part| !part.is_empty())
        .fold(root.to_path_buf(), |path, part| path.join(part))
}

struct SearchPlan {
    prefixes: Vec<String>,
    star_star_names: Vec<String>,
}

impl SearchPlan {
    fn from_contents(contents: &str) -> Self {
        let mut prefixes = Vec::new();
        let mut star_star_names = Vec::new();
        for line in contents.lines() {
            let Some(pattern) = gitignore_pattern(line) else {
                continue;
            };
            let pattern = pattern.strip_prefix('!').unwrap_or(pattern);
            let pattern = pattern.strip_prefix('/').unwrap_or(pattern);
            let pattern = pattern.strip_suffix('/').unwrap_or(pattern);
            if pattern.is_empty() {
                continue;
            }
            if let Some(rest) = pattern.strip_prefix("**/") {
                if let Some(name) = rest.split('/').next() {
                    if !name.is_empty() && !is_globby(name) {
                        star_star_names.push(name.to_string());
                    }
                }
            }
            if let Some(prefix) = literal_dir_prefix(pattern) {
                prefixes.push(prefix);
            }
        }
        prefixes.sort();
        prefixes.dedup();
        star_star_names.sort();
        star_star_names.dedup();
        Self {
            prefixes,
            star_star_names,
        }
    }

    fn walk_roots(&self, ignored_dir: &str, matcher: &Gitignore) -> Vec<String> {
        let mut roots = Vec::new();
        if is_selected(matcher, Path::new(ignored_dir), true) {
            roots.push(ignored_dir.to_string());
        }
        for prefix in &self.prefixes {
            if prefix == ignored_dir || prefix.starts_with(&format!("{ignored_dir}/")) {
                roots.push(prefix.clone());
            } else if ignored_dir.starts_with(&format!("{prefix}/")) {
                roots.push(ignored_dir.to_string());
            }
        }
        if self.star_star_names.iter().any(|name| {
            ignored_dir == name.as_str() || ignored_dir.split('/').any(|part| part == name)
        }) {
            roots.push(ignored_dir.to_string());
        }
        roots.sort();
        roots.dedup();
        roots
    }
}

fn gitignore_pattern(line: &str) -> Option<&str> {
    let line = line.trim();
    if line.is_empty() || line.starts_with('#') {
        return None;
    }
    Some(line)
}

fn literal_dir_prefix(pattern: &str) -> Option<String> {
    let mut parts = Vec::new();
    for part in pattern.split('/') {
        if part == "**" || is_globby(part) {
            break;
        }
        if part.is_empty() || part == "." {
            continue;
        }
        if part == ".." {
            return None;
        }
        parts.push(part);
    }
    if parts.is_empty() {
        None
    } else {
        Some(parts.join("/"))
    }
}

fn is_globby(part: &str) -> bool {
    part.contains('*') || part.contains('?') || part.contains('[')
}

#[cfg(test)]
mod tests {
    use super::*;
    use git2::{IndexAddOption, Repository, Signature};
    use std::fs;
    use std::path::Path;

    fn init_repo(root: &Path) -> Repository {
        let repository = Repository::init(root).unwrap();
        fs::write(root.join("README.md"), "hello\n").unwrap();
        commit(&repository, "initial");
        repository
    }

    fn commit(repository: &Repository, message: &str) {
        let mut index = repository.index().unwrap();
        index
            .add_all(["."].iter(), IndexAddOption::DEFAULT, None)
            .unwrap();
        index.write().unwrap();
        let tree_id = index.write_tree().unwrap();
        let tree = repository.find_tree(tree_id).unwrap();
        let sig = Signature::now("Test", "test@example.com").unwrap();
        let parent = repository
            .head()
            .ok()
            .and_then(|head| head.peel_to_commit().ok());
        let parents: Vec<&git2::Commit> = parent.iter().collect();
        repository
            .commit(Some("HEAD"), &sig, &sig, message, &tree, &parents)
            .unwrap();
    }

    fn sources(rules: &[WorktreeCopyRule]) -> Vec<&str> {
        rules.iter().map(|rule| rule.from.as_str()).collect()
    }

    #[test]
    fn missing_file_is_a_noop() {
        let dir = tempfile::tempdir().unwrap();
        init_repo(dir.path());
        assert!(expand_worktree_include(dir.path()).unwrap().is_empty());
        assert!(!has_worktree_include(dir.path()));
    }

    #[test]
    fn copies_gitignored_matches_and_skips_tracked_or_unignored_files() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        init_repo(root);
        fs::write(root.join(".gitignore"), ".env*\n").unwrap();
        fs::write(root.join(".worktreeinclude"), ".env*\nnotes.txt\n").unwrap();
        fs::write(root.join(".env.tracked"), "TRACKED=1\n").unwrap();
        let repository = Repository::open(root).unwrap();
        let mut index = repository.index().unwrap();
        index.add_path(Path::new(".gitignore")).unwrap();
        index.add_path(Path::new(".worktreeinclude")).unwrap();
        index.add_path(Path::new(".env.tracked")).unwrap();
        index.write().unwrap();
        commit(&repository, "ignore rules");
        fs::write(root.join(".env"), "SECRET=1\n").unwrap();
        fs::write(root.join(".env.local"), "LOCAL=1\n").unwrap();
        fs::write(root.join("notes.txt"), "not ignored\n").unwrap();

        let rules = expand_worktree_include(root).unwrap();
        assert_eq!(sources(&rules), vec![".env", ".env.local"]);
        assert!(has_worktree_include(root));
    }

    #[test]
    fn copies_files_inside_an_ignored_directory_when_the_pattern_names_it() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        init_repo(root);
        fs::write(root.join(".gitignore"), "certs/local/\nnode_modules/\n").unwrap();
        fs::write(
            root.join(".worktreeinclude"),
            "# local certs\ncerts/local/**\n",
        )
        .unwrap();
        commit(&Repository::open(root).unwrap(), "ignore dirs");
        fs::create_dir_all(root.join("certs/local")).unwrap();
        fs::write(root.join("certs/local/dev.pem"), "pem\n").unwrap();
        fs::create_dir_all(root.join("node_modules/pkg")).unwrap();
        fs::write(root.join("node_modules/pkg/.env"), "nope\n").unwrap();

        let rules = expand_worktree_include(root).unwrap();
        assert_eq!(sources(&rules), vec!["certs/local/dev.pem"]);
    }

    #[test]
    fn negation_excludes_matching_files_inside_an_ignored_directory() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        init_repo(root);
        fs::write(root.join(".gitignore"), ".local-secrets/\n").unwrap();
        fs::write(
            root.join(".worktreeinclude"),
            ".local-secrets/**\n!.local-secrets/**/*.example\n",
        )
        .unwrap();
        commit(&Repository::open(root).unwrap(), "secrets dir");
        fs::create_dir_all(root.join(".local-secrets")).unwrap();
        fs::write(root.join(".local-secrets/token"), "secret\n").unwrap();
        fs::write(root.join(".local-secrets/token.example"), "example\n").unwrap();

        let rules = expand_worktree_include(root).unwrap();
        assert_eq!(sources(&rules), vec![".local-secrets/token"]);
    }

    #[test]
    fn root_anchored_patterns_do_not_match_nested_paths() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        init_repo(root);
        fs::write(
            root.join(".gitignore"),
            "config/local.json\npackages/app/config/local.json\n",
        )
        .unwrap();
        fs::write(root.join(".worktreeinclude"), "/config/local.json\n").unwrap();
        fs::create_dir_all(root.join("config")).unwrap();
        fs::create_dir_all(root.join("packages/app/config")).unwrap();
        fs::write(root.join("config/local.json"), "{}\n").unwrap();
        fs::write(root.join("packages/app/config/local.json"), "{}\n").unwrap();
        commit(&Repository::open(root).unwrap(), "config files ignored");

        let rules = expand_worktree_include(root).unwrap();
        assert_eq!(sources(&rules), vec!["config/local.json"]);
    }

    #[test]
    fn comments_and_blank_lines_are_ignored() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        init_repo(root);
        fs::write(root.join(".gitignore"), ".env.local\n").unwrap();
        fs::write(
            root.join(".worktreeinclude"),
            "\n# keep local env\n\n.env.local\n",
        )
        .unwrap();
        commit(&Repository::open(root).unwrap(), "env ignore");
        fs::write(root.join(".env.local"), "LOCAL=1\n").unwrap();

        let rules = expand_worktree_include(root).unwrap();
        assert_eq!(sources(&rules), vec![".env.local"]);
    }
}
