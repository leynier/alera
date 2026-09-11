# SSH Hosts

## SSH Targets

Register hosts and install the Alera runtime sidecar. Bootstrap is sidecar only; it does not create a remote Git worktree. After bootstrap, `alera workspace add --host-id <id>` or Desktop New Workspace creates the worktree on that host. Terminals and `workspace.files.*` then attach over SSH. Missing, not-bootstrapped, and unreachable hosts fail with an actionable error.

List saved hosts, probe live connectivity, or remove a saved target. Status persists `lastStatus` (`reachable`, `unreachable`, or `runtimeReady`) plus `lastCheckedAt`:

```bash
alera ssh-target --json list
alera ssh-target --json add --alias build-mac --host mac.example.test --username leynier --auth agent
alera ssh-target --json status
alera ssh-target --json status --id <target-id>
alera ssh-target --json remove --id <target-id>
```

Unknown ids fail with `ssh target not found`. Duplicate aliases, including different casing, fail with `ssh target alias already exists`. `status` without `--id` probes every saved target and returns a JSON array.
