//! Remote managed-workspace worktree removal scripts (POSIX + PowerShell).

use crate::ssh_bootstrap::{powershell_string, shell_quote};

pub(crate) fn remove_worktree_script(
    windows: bool,
    repo_path: &str,
    worktree_path: &str,
    branch_to_delete: Option<&str>,
) -> String {
    if windows {
        let expected = branch_to_delete.unwrap_or("");
        let branch = branch_to_delete
            .map(|branch| {
                format!(
                    "git -C $repo branch -D {}\nif ($LASTEXITCODE -ne 0) {{ }}\n",
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
if (Test-Path -LiteralPath $worktree) {{
  if (-not [string]::IsNullOrWhiteSpace($expected)) {{
    $live = (git -C $worktree rev-parse --abbrev-ref HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) {{ throw "failed reading live branch for worktree: $worktree" }}
    if ($live -ne $expected) {{
      throw "Workspace branch does not match registered worktree: expected $expected, found $live"
    }}
  }}
}}
if (Test-Path -LiteralPath $repo) {{
  git -C $repo worktree remove --force $worktree
  {branch}
}}
if (Test-Path -LiteralPath $worktree) {{
  Remove-Item -LiteralPath $worktree -Recurse -Force
}}
"#,
            repo = powershell_string(repo_path),
            worktree = powershell_string(worktree_path),
            expected = powershell_string(expected),
            branch = branch,
        )
    } else {
        let expected = branch_to_delete.unwrap_or("");
        let branch = branch_to_delete
            .map(|branch| {
                format!(
                    "git -C \"$REPO\" branch -D {} >/dev/null 2>&1 || true\n",
                    shell_quote(branch)
                )
            })
            .unwrap_or_default();
        format!(
            r#"set -eu
export GIT_TERMINAL_PROMPT=0
REPO={repo}
WORKTREE={worktree}
EXPECTED={expected}
if [ -e "$WORKTREE" ]; then
  if [ -n "$EXPECTED" ]; then
    LIVE=$(git -C "$WORKTREE" rev-parse --abbrev-ref HEAD)
    if [ "$LIVE" != "$EXPECTED" ]; then
      printf 'Workspace branch does not match registered worktree: expected %s, found %s\n' "$EXPECTED" "$LIVE" >&2
      exit 1
    fi
  fi
fi
if [ -d "$REPO" ]; then
  git -C "$REPO" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
  {branch}
fi
rm -rf "$WORKTREE"
"#,
            repo = shell_quote(repo_path),
            worktree = shell_quote(worktree_path),
            expected = shell_quote(expected),
            branch = branch,
        )
    }
}
