//! List and read files in a remote SSH workspace through the bootstrap SSH path.

use alera_core::runtime::{RuntimeStore, Workspace};
use alera_core::workspace_files::{
    list_workspace_children, WorkspaceExplorerEntry, WorkspaceExplorerEntryKind,
};
use anyhow::{anyhow, Context, Result};
use serde_json::{json, Value};

use crate::ssh_bootstrap::{powershell_string, shell_quote};
use crate::ssh_remote::{
    is_remote_host_id, probe_or_unreachable, require_bootstrapped_ssh_target, LiveSshRemoteHost,
    RemoteHostExecutor,
};

const MAX_LIST_ENTRIES: usize = 500;
const MAX_READ_BYTES: u64 = alera_core::workspace_files::MAX_REMOTE_READ_BYTES;

pub(crate) async fn list_workspace_files(
    store: &RuntimeStore,
    workspace: &Workspace,
    relative_path: &str,
    hide_ignored: bool,
) -> Result<Vec<WorkspaceExplorerEntry>> {
    if !is_remote_host_id(Some(&workspace.host_id)) {
        return list_workspace_children(&workspace.path, relative_path, hide_ignored)
            .map_err(|error| anyhow!(error.to_string()));
    }
    list_remote_workspace_files(
        store,
        workspace,
        relative_path,
        hide_ignored,
        &LiveSshRemoteHost,
    )
    .await
}

pub(crate) async fn read_workspace_file(
    store: &RuntimeStore,
    workspace: &Workspace,
    relative_path: &str,
    offset: u64,
    length: u64,
) -> Result<RemoteFileRange> {
    if is_remote_host_id(Some(&workspace.host_id)) {
        return read_remote_workspace_file(
            store,
            workspace,
            relative_path,
            offset,
            length,
            &LiveSshRemoteHost,
        )
        .await;
    }
    let range = alera_core::workspace_files::read_workspace_file_range_from_root(
        &alera_core::workspace_files::open_workspace_file_root(&workspace.path)
            .map_err(|error| anyhow!(error.to_string()))?,
        relative_path,
        offset,
        length.min(MAX_READ_BYTES),
    )
    .map_err(|error| anyhow!(error.to_string()))?;
    Ok(RemoteFileRange {
        relative_path: relative_path.to_string(),
        offset: range.offset,
        next_offset: range.next_offset,
        total_bytes: range.total_bytes,
        mime_type: range.mime_type,
        is_text: range.is_text,
        bytes: range.bytes,
    })
}

pub(crate) struct RemoteFileRange {
    pub relative_path: String,
    pub offset: u64,
    pub next_offset: u64,
    pub total_bytes: u64,
    pub mime_type: String,
    pub is_text: bool,
    pub bytes: Vec<u8>,
}

impl RemoteFileRange {
    pub(crate) fn to_json(&self) -> Value {
        json!({
            "relativePath": self.relative_path,
            "offset": self.offset,
            "nextOffset": self.next_offset,
            "totalBytes": self.total_bytes,
            "mimeType": self.mime_type,
            "isText": self.is_text,
            "dataBase64": base64::Engine::encode(
                &base64::engine::general_purpose::STANDARD,
                &self.bytes,
            ),
        })
    }
}

/// Host-request adapter: remote workspaces only. Returns `Ok(None)` for local.
pub(crate) async fn try_read_remote_from_payload(
    store: &RuntimeStore,
    workspace: &Workspace,
    payload: &Value,
) -> Result<Option<Value>> {
    if !is_remote_host_id(Some(&workspace.host_id)) {
        return Ok(None);
    }
    let relative_path = payload
        .get("relativePath")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow!("relativePath is required"))?;
    let offset = payload.get("offset").and_then(Value::as_u64).unwrap_or(0);
    let length = payload
        .get("length")
        .and_then(Value::as_u64)
        .unwrap_or(MAX_READ_BYTES);
    let range = read_workspace_file(store, workspace, relative_path, offset, length).await?;
    Ok(Some(range.to_json()))
}

pub(crate) fn entries_to_json(entries: &[WorkspaceExplorerEntry]) -> Value {
    json!({
        "entries": entries
            .iter()
            .map(|entry| json!({
                "relativePath": entry.relative_path,
                "name": entry.name,
                "kind": entry.kind.as_str(),
                "size": entry.size,
                "isHidden": entry.is_hidden,
                "hasChildrenHint": entry.has_children_hint,
            }))
            .collect::<Vec<_>>(),
    })
}

pub(crate) async fn list_remote_workspace_files<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    workspace: &Workspace,
    relative_path: &str,
    hide_ignored: bool,
    executor: &E,
) -> Result<Vec<WorkspaceExplorerEntry>> {
    validate_relative(relative_path)?;
    let target = require_bootstrapped_ssh_target(store, &workspace.host_id).await?;
    let windows = probe_or_unreachable(executor, &target).await?;
    let directory = join_remote(&workspace.path, relative_path, windows);
    let stdout = executor
        .run(&target, windows, &list_script(windows, &directory))
        .await
        .with_context(|| {
            format!(
                "failed listing files on host '{}'. Confirm the host is reachable with `alera ssh-target status --id {}`.",
                target.alias, target.id
            )
        })?;
    let mut entries = parse_list_output(&stdout, relative_path)?;
    if hide_ignored {
        entries.retain(|entry| !entry.is_hidden && entry.name != ".git");
    }
    entries.truncate(MAX_LIST_ENTRIES);
    Ok(entries)
}

pub(crate) async fn read_remote_workspace_file<E: RemoteHostExecutor>(
    store: &RuntimeStore,
    workspace: &Workspace,
    relative_path: &str,
    offset: u64,
    length: u64,
    executor: &E,
) -> Result<RemoteFileRange> {
    validate_relative(relative_path)?;
    let target = require_bootstrapped_ssh_target(store, &workspace.host_id).await?;
    let windows = probe_or_unreachable(executor, &target).await?;
    let file_path = join_remote(&workspace.path, relative_path, windows);
    let length = length.min(MAX_READ_BYTES);
    let stdout = executor
        .run(
            &target,
            windows,
            &read_script(windows, &file_path, offset, length),
        )
        .await
        .with_context(|| {
            format!(
                "failed reading files on host '{}'. Confirm the host is reachable with `alera ssh-target status --id {}`.",
                target.alias, target.id
            )
        })?;
    parse_read_output(relative_path, offset, &stdout)
}

fn validate_relative(relative_path: &str) -> Result<()> {
    if relative_path.starts_with('/')
        || relative_path.starts_with('\\')
        || relative_path.split(['/', '\\']).any(|part| part == "..")
    {
        bail_invalid_path(relative_path)
    } else {
        Ok(())
    }
}

fn bail_invalid_path(relative_path: &str) -> Result<()> {
    anyhow::bail!("workspace path is invalid: {relative_path}")
}

fn join_remote(root: &str, relative: &str, windows: bool) -> String {
    if relative.is_empty() {
        return root.to_string();
    }
    crate::ssh_bootstrap::remote_join(if windows { "windows" } else { "posix" }, root, &[relative])
}

fn list_script(windows: bool, directory: &str) -> String {
    if windows {
        format!(
            r#"$ErrorActionPreference = 'Stop'
$path = {path}
Get-ChildItem -LiteralPath $path -Force | ForEach-Object {{
  $kind = if ($_.PSIsContainer) {{ 'directory' }} elseif ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) {{ 'symlink' }} elseif (-not $_.PSIsContainer) {{ 'file' }} else {{ 'other' }}
  $hidden = [bool]($_.Attributes -band [IO.FileAttributes]::Hidden) -or $_.Name.StartsWith('.')
  Write-Output ('{{"name":' + (ConvertTo-Json -Compress $_.Name) + ',"kind":"' + $kind + '","size":' + [int64]$_.Length + ',"isHidden":' + $hidden.ToString().ToLower() + '}}')
}}
"#,
            path = powershell_string(directory),
        )
    } else {
        format!(
            r#"set -eu
cd -- {directory}
find . -maxdepth 1 -mindepth 1 -print | sort | while IFS= read -r entry; do
  name=${{entry#./}}
  if [ -L "$name" ]; then kind=symlink
  elif [ -d "$name" ]; then kind=directory
  elif [ -f "$name" ]; then kind=file
  else kind=other
  fi
  if [ -f "$name" ]; then
    size=$(wc -c < "$name" 2>/dev/null | tr -d ' ')
  else
    size=0
  fi
  case "$size" in ''|*[!0-9]*) size=0 ;; esac
  hidden=false
  case "$name" in .* ) hidden=true ;; esac
  printf '{{"name":"%s","kind":"%s","size":%s,"isHidden":%s}}\n' "$(printf '%s' "$name" | sed 's/"/\\"/g')" "$kind" "$size" "$hidden"
done
"#,
            directory = shell_quote(directory),
        )
    }
}

fn read_script(windows: bool, file_path: &str, offset: u64, length: u64) -> String {
    if windows {
        format!(
            r#"$ErrorActionPreference = 'Stop'
$path = {path}
$info = Get-Item -LiteralPath $path
$total = [int64]$info.Length
$offset = [int64]{offset}
$length = [int64]{length}
if ($offset -gt $total) {{ $offset = $total }}
$remain = $total - $offset
if ($length -gt $remain) {{ $length = $remain }}
$stream = [IO.File]::OpenRead($path)
try {{
  $null = $stream.Seek($offset, 'Begin')
  $buffer = New-Object byte[] $length
  $read = $stream.Read($buffer, 0, $buffer.Length)
  $bytes = New-Object byte[] $read
  [Array]::Copy($buffer, $bytes, $read)
  $b64 = [Convert]::ToBase64String($bytes)
}} finally {{
  $stream.Dispose()
}}
Write-Output $total
Write-Output $b64
"#,
            path = powershell_string(file_path),
            offset = offset,
            length = length,
        )
    } else {
        format!(
            r#"set -eu
FILE={file}
if [ ! -f "$FILE" ]; then
  echo 'file not found' >&2
  exit 1
fi
total=$(wc -c < "$FILE" | tr -d ' ')
printf '%s\n' "$total"
dd if="$FILE" bs=1 skip={offset} count={length} 2>/dev/null | base64 | tr -d '\n'
printf '\n'
"#,
            file = shell_quote(file_path),
            offset = offset,
            length = length,
        )
    }
}

fn parse_list_output(stdout: &str, relative_path: &str) -> Result<Vec<WorkspaceExplorerEntry>> {
    let mut entries = Vec::new();
    for line in stdout
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
    {
        let value: Value = serde_json::from_str(line)
            .with_context(|| format!("remote file list was not JSON: {line}"))?;
        let name = value
            .get("name")
            .and_then(Value::as_str)
            .ok_or_else(|| anyhow!("remote file list is missing name"))?;
        let kind = match value.get("kind").and_then(Value::as_str).unwrap_or("other") {
            "directory" => WorkspaceExplorerEntryKind::Directory,
            "symlink" => WorkspaceExplorerEntryKind::Symlink,
            "file" => WorkspaceExplorerEntryKind::File,
            _ => WorkspaceExplorerEntryKind::Other,
        };
        let size = value.get("size").and_then(Value::as_u64).unwrap_or(0);
        let is_hidden = value
            .get("isHidden")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let child = if relative_path.is_empty() {
            name.to_string()
        } else {
            format!("{relative_path}/{name}")
        };
        entries.push(WorkspaceExplorerEntry {
            relative_path: child,
            name: name.to_string(),
            kind,
            size,
            is_hidden,
            has_children_hint: matches!(kind, WorkspaceExplorerEntryKind::Directory),
        });
    }
    Ok(entries)
}

fn parse_read_output(relative_path: &str, offset: u64, stdout: &str) -> Result<RemoteFileRange> {
    let mut lines = stdout
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty());
    let total_bytes = lines
        .next()
        .ok_or_else(|| anyhow!("remote file read returned no size"))?
        .parse::<u64>()
        .context("remote file read size was not a number")?;
    let b64 = lines.next().unwrap_or("");
    let bytes = if b64.is_empty() {
        Vec::new()
    } else {
        base64::Engine::decode(&base64::engine::general_purpose::STANDARD, b64)
            .context("remote file read was not valid base64")?
    };
    let next_offset = offset.saturating_add(bytes.len() as u64);
    Ok(RemoteFileRange {
        relative_path: relative_path.to_string(),
        offset,
        next_offset,
        total_bytes,
        mime_type: "application/octet-stream".to_string(),
        is_text: std::str::from_utf8(&bytes).is_ok(),
        bytes,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn posix_list_script_emits_numeric_size_for_directories() {
        let script = list_script(false, "/tmp");
        assert!(
            script.contains(r#"case "$size" in ''|*[!0-9]*) size=0 ;; esac"#),
            "posix list script must coerce empty wc output to 0: {script}"
        );
        assert!(
            script.contains(r#"if [ -f "$name" ]; then"#),
            "posix list script must only wc regular files: {script}"
        );
    }

    #[test]
    fn parse_list_accepts_ndjson() {
        let stdout = r#"{"name":"src","kind":"directory","size":0,"isHidden":false}
{"name":".env","kind":"file","size":4,"isHidden":true}
"#;
        let entries = parse_list_output(stdout, "").unwrap();
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].name, "src");
        assert_eq!(entries[0].kind, WorkspaceExplorerEntryKind::Directory);
        assert!(entries[1].is_hidden);
    }

    #[test]
    fn parse_read_accepts_size_then_base64() {
        let stdout = format!(
            "5\n{}\n",
            base64::Engine::encode(&base64::engine::general_purpose::STANDARD, b"hello")
        );
        let range = parse_read_output("README.md", 0, &stdout).unwrap();
        assert_eq!(range.total_bytes, 5);
        assert_eq!(range.bytes, b"hello");
        assert!(range.is_text);
    }

    #[test]
    fn rejects_parent_relative_paths() {
        assert!(validate_relative("../secret").is_err());
        assert!(validate_relative("/etc/passwd").is_err());
        assert!(validate_relative("src/main.rs").is_ok());
    }
}
