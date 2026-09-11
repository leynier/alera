//! Remote managed-workspace worktree removal scripts (POSIX + PowerShell).

use crate::ssh_bootstrap::{powershell_string, shell_quote};

pub(crate) fn remove_worktree_script(
    windows: bool,
    repo_path: &str,
    worktree_path: &str,
    branch_to_delete: Option<&str>,
) -> String {
    worktree_removal_script(windows, repo_path, worktree_path, branch_to_delete, false)
}

pub(crate) fn validate_worktree_removal_script(
    windows: bool,
    repo_path: &str,
    worktree_path: &str,
    branch: Option<&str>,
) -> String {
    worktree_removal_script(windows, repo_path, worktree_path, branch, true)
}

fn worktree_removal_script(
    windows: bool,
    repo_path: &str,
    worktree_path: &str,
    branch_to_delete: Option<&str>,
    preflight_only: bool,
) -> String {
    if windows {
        let expected = branch_to_delete.unwrap_or("");
        format!(
            r#"$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$env:GIT_TERMINAL_PROMPT = '0'
$repo = {repo}
$worktree = {worktree}
$expected = {expected}
if (-not [string]::IsNullOrWhiteSpace($expected)) {{
  $keepBranch = $false
  try {{
  if (-not (Test-Path -LiteralPath $worktree)) {{ $keepBranch = $true }}
  else {{
    $defaultBranch = git -C $repo symbolic-ref --short refs/remotes/origin/HEAD 2>$null
    if ($LASTEXITCODE -ne 0) {{ $defaultBranch = '' }}
    $defaultBranch = $defaultBranch -replace '^origin/', ''
    if ([string]::IsNullOrWhiteSpace($defaultBranch)) {{
      $defaultBranch = git -C $repo config --get init.defaultBranch 2>$null
      if ($LASTEXITCODE -ne 0) {{ $defaultBranch = '' }}
      if (-not [string]::IsNullOrWhiteSpace($defaultBranch)) {{
        git -C $repo show-ref --verify --quiet "refs/heads/$defaultBranch" 2>$null
        if ($LASTEXITCODE -ne 0) {{
          git -C $repo show-ref --verify --quiet "refs/remotes/origin/$defaultBranch" 2>$null
          if ($LASTEXITCODE -ne 0) {{ $defaultBranch = '' }}
        }}
      }}
    }}
    if ([string]::IsNullOrWhiteSpace($defaultBranch)) {{
      foreach ($candidate in @('main', 'master')) {{
        git -C $repo show-ref --verify --quiet "refs/heads/$candidate" 2>$null
        if ($LASTEXITCODE -eq 0) {{ $defaultBranch = $candidate; break }}
        git -C $repo show-ref --verify --quiet "refs/remotes/origin/$candidate" 2>$null
        if ($LASTEXITCODE -eq 0) {{ $defaultBranch = $candidate; break }}
      }}
    }}
    if ([string]::IsNullOrWhiteSpace($defaultBranch)) {{
      $defaultBranch = git -C $repo symbolic-ref --short HEAD 2>$null
      if ($LASTEXITCODE -ne 0) {{ $defaultBranch = '' }}
    }}
    if ([string]::IsNullOrWhiteSpace($defaultBranch) -or $defaultBranch -eq $expected) {{ $keepBranch = $true }}
    else {{
      $merged = $false
      foreach ($ref in @($defaultBranch, "origin/$defaultBranch")) {{
        git -C $repo rev-parse --verify $ref 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {{ continue }}
        git -C $repo merge-base --is-ancestor $expected $ref 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {{ $merged = $true; break }}
        $result = git -C $repo merge-tree --write-tree $ref $expected 2>$null
        if ($LASTEXITCODE -eq 0) {{
          $tree = git -C $repo rev-parse ($ref + '^{{tree}}')
          if ($result.Trim() -eq $tree.Trim()) {{ $merged = $true; break }}
        }}
      }}
      if (-not $merged) {{ $keepBranch = $true }}
    }}
    if (-not $keepBranch) {{
      $live = (git -C $worktree rev-parse --abbrev-ref HEAD 2>$null)
      if ($LASTEXITCODE -ne 0 -or $live -ne $expected) {{ $keepBranch = $true }}
      $owners = @(git -C $repo worktree list --porcelain 2>$null | Where-Object {{ $_ -eq "branch refs/heads/$expected" }})
      if ($LASTEXITCODE -ne 0 -or $owners.Count -ne 1) {{ $keepBranch = $true }}
    }}
  }}
  }} catch {{
    $keepBranch = $true
  }}
  if ($keepBranch) {{ $expected = '' }}
}}
if (-not (Test-Path -LiteralPath $repo)) {{ throw 'Repository unavailable; no cleanup performed' }}
if ({preflight}) {{ return }}
if (Test-Path -LiteralPath $worktree) {{
  git -C $repo worktree remove --force $worktree
  if ($LASTEXITCODE -ne 0) {{ throw 'Worktree removal failed; branch retained' }}
  if (-not [string]::IsNullOrWhiteSpace($expected)) {{
    try {{
      git -C $repo update-ref -d "refs/heads/$expected" 2>$null | Out-Null
    }} catch {{}}
  }}
}}
"#,
            repo = powershell_string(repo_path),
            worktree = powershell_string(worktree_path),
            expected = powershell_string(expected),
            preflight = if preflight_only { "$true" } else { "$false" },
        )
    } else {
        let expected = branch_to_delete.unwrap_or("");
        format!(
            r#"set -eu
export GIT_TERMINAL_PROMPT=0
REPO={repo}
WORKTREE={worktree}
EXPECTED={expected}
if [ -n "$EXPECTED" ]; then
  KEEP_BRANCH=0
  if [ ! -e "$WORKTREE" ]; then
    KEEP_BRANCH=1
  else
    DEFAULT=$(git -C "$REPO" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)
    DEFAULT=${{DEFAULT#origin/}}
    if [ -z "$DEFAULT" ]; then
      DEFAULT=$(git -C "$REPO" config --get init.defaultBranch 2>/dev/null || true)
      if [ -n "$DEFAULT" ] \
        && ! git -C "$REPO" show-ref --verify --quiet "refs/heads/$DEFAULT" \
        && ! git -C "$REPO" show-ref --verify --quiet "refs/remotes/origin/$DEFAULT"; then
        DEFAULT=""
      fi
    fi
    if [ -z "$DEFAULT" ]; then
      for CANDIDATE in main master; do
        if git -C "$REPO" show-ref --verify --quiet "refs/heads/$CANDIDATE" \
          || git -C "$REPO" show-ref --verify --quiet "refs/remotes/origin/$CANDIDATE"; then
          DEFAULT=$CANDIDATE
          break
        fi
      done
    fi
    if [ -z "$DEFAULT" ]; then
      DEFAULT=$(git -C "$REPO" symbolic-ref --short HEAD 2>/dev/null || true)
    fi
    if [ -z "$DEFAULT" ] || [ "$EXPECTED" = "$DEFAULT" ]; then
      KEEP_BRANCH=1
    else
      merged=0
      for REF in "$DEFAULT" "origin/$DEFAULT"; do
        if git -C "$REPO" rev-parse --verify "$REF" >/dev/null 2>&1; then
          if git -C "$REPO" merge-base --is-ancestor "$EXPECTED" "$REF"; then
            merged=1
            break
          fi
          RESULT=$(git -C "$REPO" merge-tree --write-tree "$REF" "$EXPECTED" 2>/dev/null || true)
          TREE=$(git -C "$REPO" rev-parse "$REF^{{tree}}" 2>/dev/null || true)
          if [ -n "$RESULT" ] && [ "$RESULT" = "$TREE" ]; then
            merged=1
            break
          fi
        fi
      done
      if [ "$merged" -eq 0 ]; then KEEP_BRANCH=1; fi
    fi
    if [ "$KEEP_BRANCH" -eq 0 ]; then
      LIVE=$(git -C "$WORKTREE" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
      if [ -z "$LIVE" ] || [ "$LIVE" != "$EXPECTED" ]; then KEEP_BRANCH=1; fi
      OWNERS=$(git -C "$REPO" worktree list --porcelain 2>/dev/null | awk -v ref="branch refs/heads/$EXPECTED" '$0 == ref {{ n++ }} END {{ print n+0 }}' || true)
      if [ "$OWNERS" != 1 ]; then KEEP_BRANCH=1; fi
    fi
  fi
  if [ "$KEEP_BRANCH" -eq 1 ]; then EXPECTED=""; fi
fi
[ -d "$REPO" ] || {{ printf '%s\n' 'Repository unavailable; no cleanup performed' >&2; exit 1; }}
{preflight}
if [ -e "$WORKTREE" ]; then
  git -C "$REPO" worktree remove --force "$WORKTREE"
  if [ -n "$EXPECTED" ]; then
    git -C "$REPO" update-ref -d "refs/heads/$EXPECTED" || true
  fi
fi
"#,
            repo = shell_quote(repo_path),
            worktree = shell_quote(worktree_path),
            expected = shell_quote(expected),
            preflight = if preflight_only { "exit 0" } else { "" },
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn both_platforms_preflight_before_removal_and_never_force_delete_branches() {
        for windows in [false, true] {
            let script = remove_worktree_script(windows, "/repo", "/child", Some("feature"));
            assert!(
                script.find("merge-base --is-ancestor").unwrap()
                    < script.find("worktree remove").unwrap()
            );
            assert!(script.contains("merge-tree --write-tree"));
            assert!(script.contains("update-ref -d"));
            assert!(!script.contains("branch -D"));
            assert!(!script.contains("rm -rf"));
            assert!(!script.contains("Remove-Item"));
            assert!(!script.contains("DEFAULT=main"));
            assert!(!script.contains("$defaultBranch = 'main'"));
            let preflight =
                validate_worktree_removal_script(windows, "/repo", "/child", Some("feature"));
            let stop = if windows {
                "if ($true) { return }"
            } else {
                "exit 0"
            };
            assert!(preflight.find(stop).unwrap() < preflight.find("worktree remove").unwrap());
        }
        let posix = remove_worktree_script(false, "/repo", "/child", Some("feature"));
        assert!(posix.contains("rev-parse --abbrev-ref HEAD 2>/dev/null || true"));
        assert!(posix.contains("update-ref -d \"refs/heads/$EXPECTED\" || true"));
        let windows = remove_worktree_script(true, "/repo", "/child", Some("feature"));
        assert!(windows.contains("$PSNativeCommandUseErrorActionPreference = $false"));
        let merge_at = windows
            .find("merge-base --is-ancestor")
            .expect("merge-base");
        assert!(windows[..merge_at].contains("try {"));
        assert!(windows[merge_at..].contains("catch {"));
        let delete_at = windows.find("update-ref -d").expect("update-ref");
        let try_at = windows[..delete_at]
            .rfind("try {")
            .expect("try before update-ref");
        let catch_at = windows[delete_at..]
            .find("catch {}")
            .expect("catch after update-ref");
        assert!(try_at < delete_at);
        assert!(catch_at > 0);
    }

    #[cfg(unix)]
    #[test]
    fn posix_unmerged_branch_keeps_branch_and_removes_worktree() {
        let temp = tempfile::tempdir().unwrap();
        let repo = temp.path().join("repo");
        let child = temp.path().join("child");
        std::fs::create_dir(&repo).unwrap();
        let git = |dir: &std::path::Path, args: &[&str]| {
            alera_core::git_cli::git_in_dir(dir, args).unwrap()
        };
        git(&repo, &["init", "-b", "main"]);
        git(&repo, &["config", "user.name", "Test"]);
        git(&repo, &["config", "user.email", "test@example.com"]);
        git(&repo, &["commit", "--allow-empty", "-m", "initial"]);
        git(
            &repo,
            &[
                "symbolic-ref",
                "refs/remotes/origin/HEAD",
                "refs/remotes/origin/main",
            ],
        );
        git(
            &repo,
            &["worktree", "add", "-b", "feature", child.to_str().unwrap()],
        );
        std::fs::write(child.join("feature.txt"), "unique").unwrap();
        git(&child, &["add", "feature.txt"]);
        git(&child, &["commit", "-m", "unmerged"]);
        let execute = |branch| {
            alera_core::child_process::windowless_command("sh")
                .args([
                    "-c",
                    &remove_worktree_script(
                        false,
                        repo.to_str().unwrap(),
                        child.to_str().unwrap(),
                        branch,
                    ),
                ])
                .output()
                .unwrap()
        };
        assert!(execute(Some("feature")).status.success());
        assert!(!child.exists());
        assert!(alera_core::git::branch_exists(repo.to_str().unwrap(), "feature").unwrap());
    }

    #[cfg(unix)]
    #[test]
    fn posix_squash_merged_branch_is_deleted() {
        let temp = tempfile::tempdir().unwrap();
        let repo = temp.path().join("repo");
        let child = temp.path().join("child");
        std::fs::create_dir(&repo).unwrap();
        let git = |dir: &std::path::Path, args: &[&str]| {
            alera_core::git_cli::git_in_dir(dir, args).unwrap()
        };
        git(&repo, &["init", "-b", "main"]);
        git(&repo, &["config", "user.name", "Test"]);
        git(&repo, &["config", "user.email", "test@example.com"]);
        git(&repo, &["commit", "--allow-empty", "-m", "initial"]);
        git(
            &repo,
            &[
                "symbolic-ref",
                "refs/remotes/origin/HEAD",
                "refs/remotes/origin/main",
            ],
        );
        git(
            &repo,
            &["worktree", "add", "-b", "feature", child.to_str().unwrap()],
        );
        std::fs::write(child.join("feature.txt"), "unique").unwrap();
        git(&child, &["add", "feature.txt"]);
        git(&child, &["commit", "-m", "feature"]);
        git(&repo, &["merge", "--squash", "feature"]);
        git(&repo, &["commit", "-m", "squash"]);
        let output = alera_core::child_process::windowless_command("sh")
            .args([
                "-c",
                &remove_worktree_script(
                    false,
                    repo.to_str().unwrap(),
                    child.to_str().unwrap(),
                    Some("feature"),
                ),
            ])
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(!child.exists());
        assert!(!alera_core::git::branch_exists(repo.to_str().unwrap(), "feature").unwrap());
    }

    #[cfg(unix)]
    #[test]
    fn posix_resolves_head_when_origin_head_is_missing() {
        let temp = tempfile::tempdir().unwrap();
        let repo = temp.path().join("repo");
        let child = temp.path().join("child");
        std::fs::create_dir(&repo).unwrap();
        let git = |dir: &std::path::Path, args: &[&str]| {
            alera_core::git_cli::git_in_dir(dir, args).unwrap()
        };
        git(&repo, &["init", "-b", "develop"]);
        git(&repo, &["config", "user.name", "Test"]);
        git(&repo, &["config", "user.email", "test@example.com"]);
        git(&repo, &["commit", "--allow-empty", "-m", "initial"]);
        git(
            &repo,
            &["worktree", "add", "-b", "feature", child.to_str().unwrap()],
        );
        std::fs::write(child.join("feature.txt"), "unique").unwrap();
        git(&child, &["add", "feature.txt"]);
        git(&child, &["commit", "-m", "feature"]);
        git(&repo, &["merge", "--squash", "feature"]);
        git(&repo, &["commit", "-m", "squash"]);
        let output = alera_core::child_process::windowless_command("sh")
            .args([
                "-c",
                &remove_worktree_script(
                    false,
                    repo.to_str().unwrap(),
                    child.to_str().unwrap(),
                    Some("feature"),
                ),
            ])
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(!child.exists());
        assert!(!alera_core::git::branch_exists(repo.to_str().unwrap(), "feature").unwrap());
    }
}
