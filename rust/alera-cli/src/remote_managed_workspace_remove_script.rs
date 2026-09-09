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
        let branch = branch_to_delete
            .map(|branch| {
                format!(
                    "git -C $repo branch -d -- {}\nif ($LASTEXITCODE -ne 0) {{ throw 'Worktree removed; branch retained because safe deletion failed' }}\n",
                    powershell_string(branch)
                )
            })
            .unwrap_or_default();
        format!(
            r#"$ErrorActionPreference = 'Stop'
$env:GIT_TERMINAL_PROMPT = '0'
$repo = {repo}
$worktree = {worktree}
$expected = {expected}
if (-not [string]::IsNullOrWhiteSpace($expected)) {{
  if (-not (Test-Path -LiteralPath $worktree)) {{ throw 'Live branch is unavailable. Keep the branch.' }}
  $defaultBranch = git -C $repo symbolic-ref --short refs/remotes/origin/HEAD 2>$null
  if ($LASTEXITCODE -ne 0) {{ throw 'Default branch is unknown. Keep the branch.' }}
  $defaultBranch = $defaultBranch -replace '^origin/', ''
  if ($defaultBranch -eq $expected) {{ throw 'The default branch must be kept' }}
  git -C $repo merge-base --is-ancestor $expected $defaultBranch
  if ($LASTEXITCODE -ne 0) {{ throw 'Branch is unmerged or safety is unknown. Keep the branch.' }}
  $owners = @(git -C $repo worktree list --porcelain | Where-Object {{ $_ -eq "branch refs/heads/$expected" }})
  if ($LASTEXITCODE -ne 0 -or $owners.Count -ne 1) {{ throw 'Branch checkout ownership is uncertain. Keep the branch.' }}
}}
if (Test-Path -LiteralPath $worktree) {{
  if (-not [string]::IsNullOrWhiteSpace($expected)) {{
    $live = (git -C $worktree rev-parse --abbrev-ref HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) {{ throw "failed reading live branch for worktree: $worktree" }}
    if ($live -ne $expected) {{
      throw "Workspace branch does not match registered worktree: expected $expected, found $live"
    }}
  }}
}}
if (-not (Test-Path -LiteralPath $repo)) {{ throw 'Repository unavailable; no cleanup performed' }}
if ({preflight}) {{ return }}
if (Test-Path -LiteralPath $worktree) {{
  git -C $repo worktree remove --force $worktree
  if ($LASTEXITCODE -ne 0) {{ throw 'Worktree removal failed; branch retained' }}
  {branch}
}}
"#,
            repo = powershell_string(repo_path),
            worktree = powershell_string(worktree_path),
            expected = powershell_string(expected),
            branch = branch,
            preflight = if preflight_only { "$true" } else { "$false" },
        )
    } else {
        let expected = branch_to_delete.unwrap_or("");
        let branch = branch_to_delete
            .map(|branch| format!("git -C \"$REPO\" branch -d -- {}\n", shell_quote(branch)))
            .unwrap_or_default();
        format!(
            r#"set -eu
export GIT_TERMINAL_PROMPT=0
REPO={repo}
WORKTREE={worktree}
EXPECTED={expected}
if [ -n "$EXPECTED" ]; then
  [ -e "$WORKTREE" ] || {{ printf '%s\n' 'Live branch is unavailable. Keep the branch.' >&2; exit 1; }}
  DEFAULT=$(git -C "$REPO" symbolic-ref --short refs/remotes/origin/HEAD) || {{ printf '%s\n' 'Default branch is unknown. Keep the branch.' >&2; exit 1; }}
  DEFAULT=${{DEFAULT#origin/}}
  [ "$EXPECTED" != "$DEFAULT" ] || {{ printf '%s\n' 'The default branch must be kept' >&2; exit 1; }}
  git -C "$REPO" merge-base --is-ancestor "$EXPECTED" "$DEFAULT" || {{ printf '%s\n' 'Branch is unmerged or safety is unknown. Keep the branch.' >&2; exit 1; }}
  OWNERS=$(git -C "$REPO" worktree list --porcelain | awk -v ref="branch refs/heads/$EXPECTED" '$0 == ref {{ n++ }} END {{ print n+0 }}')
  [ "$OWNERS" = 1 ] || {{ printf '%s\n' 'Branch checkout ownership is uncertain. Keep the branch.' >&2; exit 1; }}
fi
if [ -e "$WORKTREE" ]; then
  if [ -n "$EXPECTED" ]; then
    LIVE=$(git -C "$WORKTREE" rev-parse --abbrev-ref HEAD)
    if [ "$LIVE" != "$EXPECTED" ]; then
      printf 'Workspace branch does not match registered worktree: expected %s, found %s\n' "$EXPECTED" "$LIVE" >&2
      exit 1
    fi
  fi
fi
[ -d "$REPO" ] || {{ printf '%s\n' 'Repository unavailable; no cleanup performed' >&2; exit 1; }}
{preflight}
if [ -e "$WORKTREE" ]; then
  git -C "$REPO" worktree remove --force "$WORKTREE"
  {branch}
fi
"#,
            repo = shell_quote(repo_path),
            worktree = shell_quote(worktree_path),
            expected = shell_quote(expected),
            branch = branch,
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
            assert!(script.contains("branch -d --"));
            assert!(!script.contains("branch -D"));
            assert!(!script.contains("rm -rf"));
            assert!(!script.contains("Remove-Item"));
            let preflight =
                validate_worktree_removal_script(windows, "/repo", "/child", Some("feature"));
            let stop = if windows {
                "if ($true) { return }"
            } else {
                "exit 0"
            };
            assert!(preflight.find(stop).unwrap() < preflight.find("worktree remove").unwrap());
        }
    }

    #[cfg(unix)]
    #[test]
    fn posix_unmerged_branch_refuses_cleanup_but_explicit_keep_removes_worktree() {
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
        git(&child, &["commit", "--allow-empty", "-m", "unmerged"]);
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
        assert!(!execute(Some("feature")).status.success());
        assert!(child.exists());
        assert!(execute(None).status.success());
        assert!(!child.exists());
        assert!(alera_core::git::branch_exists(repo.to_str().unwrap(), "feature").unwrap());
    }
}
