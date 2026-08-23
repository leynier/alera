# Workspace Storage

Alera measures a linked workspace on demand before offering manual cleanup. Measurement runs in a sidecar worker rather than on Flutter's main isolate or the terminal-host actor. Directory symlinks are counted but never followed.

Cleanup is refused when the workspace is selected in the requesting workbench, has a live terminal, process, or browser session, is owned by an active automation definition or run, belongs to another host, is the main/source repository of any project, has another runtime owner, or resolves outside Alera's configured managed-workspace root. Once accepted, the runtime mutation barrier rejects new owner-creating requests until cleanup completes. Ownership, path containment, and Git worktree branch identity are checked again immediately before mutation. Cleanup removes the registered Git worktree first and only then removes runtime records. A failed Git operation leaves the records available for a retry. There is no scheduled or automatic cleanup.

## Measurement Limitations

- Reported bytes are allocated entry lengths from filesystem metadata, not guaranteed physical disk usage. Sparse files, compression, deduplication, copy-on-write clones, filesystem block size, and hard links can make actual reclaimed space differ.
- Directory metadata contributes a small platform- and filesystem-dependent amount.
- Files changing during a scan can make the result approximate. The cleanup request rechecks ownership and path safety, but it does not freeze the filesystem.
- Unreadable or concurrently removed entries fail the scan instead of presenting a cleanup confirmation.
- Windows junctions and other reparse-point behavior depends on Rust's filesystem classification for the installed toolchain. Alera does not follow entries classified as symbolic links, and path containment is still checked using the platform canonical path.
