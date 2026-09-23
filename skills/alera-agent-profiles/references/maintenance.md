# Profile Maintenance

Inspect the user-approved launch catalog:

```bash
alera agent-profile list
alera agent-profile --json show --profile-name "Codex Sol"
```

Launch a declared profile in an existing workspace. The workspace defaults to `ALERA_WORKSPACE_ID`. `--profile` is an alias for `--profile-name`:

```bash
alera agent-profile --json launch --profile "Codex Sol" --prompt "Fix the flaky test"
alera agent-profile --json launch --workspace <workspace-id> --profile-id <profile-id> --prompt-file prompt.txt
```

Create Command or Managed profiles through the authenticated runtime host:

```bash
alera agent-profile create --name "Codex Sol" --agent-type codex --launch-mode command --command "codex --search"
alera agent-profile create --name "Managed Codex" --agent-type codex --launch-mode managed --managed-config-file profile.json
```

Updates patch only the supplied fields. Use `--expected-revision` when a script must pin the revision it previously observed. Changing `--agent-type` on an existing Managed profile requires a new configuration through `--managed-config`, `--managed-config-file`, or `--managed-config-stdin`. Settings that newly reduce protections require `--confirm-reduced-protections`.

Preview removal impact before explicitly confirming deletion:

```bash
alera agent-profile removal-impact --profile-id <profile-id>
alera agent-profile remove --profile-id <profile-id> --confirm
```

Use `alera agent-profile reorder --id <id> --id <id>` with every current profile id exactly once to replace the persisted order. Keep `alera orchestration agent-profiles` for coordinator discovery; it does not mutate the catalog.

For model or quota selection, read [catalog research](catalog-research.md). For changed Managed configuration, read [managed profiles](managed-profiles.md). Inspect CLI support only for launch fields you change; a description edit or reorder needs no model research. Re-read the changed profile or order to verify persistence.
