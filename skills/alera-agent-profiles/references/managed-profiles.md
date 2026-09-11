# Managed Agent Profiles

Read this reference when creating or changing profiles, generating commands, or diagnosing a launch.

## Administrative Commands

```bash
alera agent-profile --json list
alera agent-profile --json show --profile-name "Codex Sol"
alera agent-profile create --name "Managed Codex" --agent-type codex --launch-mode managed --managed-config-file profile.json
alera agent-profile update --profile-name "Managed Codex" --expected-revision 3 --managed-config-file profile.json
alera agent-profile removal-impact --profile-name "Managed Codex"
alera agent-profile remove --profile-name "Managed Codex" --expected-revision 3 --confirm
alera agent-profile reorder --id <first-id> --id <second-id>
```

`show`, `update`, `removal-impact`, and `remove` accept a stable id or a case-insensitive unique name. Updates patch only supplied fields. Use `--clear-custom-prompt`, `--clear-description`, or `--clear-quota-group` to remove optional values.

Supply Managed configuration with exactly one of:

```bash
--managed-config '{"model":"..."}'
--managed-config-file profile.json
--managed-config-stdin
```

Prefer a file or stdin for non-trivial JSON. Changing the adapter of a Managed profile requires an explicit replacement Managed configuration.

## Current Managed Keys

These keys describe Alera's current adapter contract. Confirm the installed CLI still accepts the generated flags before relying on a profile.

| Adapter | Managed keys |
|---|---|
| `codex` | `model`, `effort`, `planModeEffort`, `sandbox`, `approvalPolicy`, `webSearch`, `bypassApprovalsAndSandbox` |
| `claude` | `model`, `effort`, `agent`, `permissionMode`, `allowSkipPermissions`, `ccsProfile` |
| `copilot` | `model`, `effort`, `agent`, `mode`, `context`, `allowAll`, `maxAiCredits`, `maxAutopilotContinues`, `noAskUser` |
| `cursor` | `model`, `mode`, `permissionMode`, `sandbox`, `trustWorkspace` |
| `agy` | `model`, `effort`, `agent`, `mode`, `skipPermissions`, `sandbox` |
| `opencode` | `model`, `agent`, `autoApprove` |
| `opencode2` | `model`, `agent`, `autoApprove`; the interactive TUI currently emits only `autoApprove` |
| `pi` | `model`, `thinking`, `projectTrust` |
| `amp` | `mode`, `fast` |
| `grok` | `model`, `effort`, `agent`, `permissionMode`, `sandbox`, `disableWebSearch` |
| `fx` | `resumeLast`, `noAdditionalDirs`, `record` |

Use `alera agent-profile create --help` and the profile command preview as the installed-runtime authority. Unknown keys fail closed.

## Reduced Protections

Profiles that introduce the following settings require explicit user approval and `--confirm-reduced-protections`:

- Codex bypass, full access, or never-ask approval.
- Claude bypass or reduced prompting.
- Copilot broad allow or autopilot settings.
- Cursor force, disabled sandbox, or trusted workspace.
- Antigravity skipped permissions.
- OpenCode auto approval.
- Pi pre-approved project trust.
- Grok Build bypass or reduced prompting.

## Quota-Aware Example

```bash
alera agent-profile create \
  --name "Codex Sol" \
  --agent-type codex \
  --launch-mode managed \
  --managed-config '{"model":"gpt-5.6-sol","effort":"high","planModeEffort":"high","webSearch":true,"bypassApprovalsAndSandbox":true}' \
  --description "Hard agentic implementation and deep debugging. Same quota as other Codex profiles, so do not use them as quota fallbacks." \
  --quota-group codex \
  --confirm-reduced-protections
```

The model slug is illustrative. Discover the user's actual available models before creating a profile.

## Adapter Traps

### OpenCode

Do not infer OpenCode behavior from the package name or a stale symlink. Inspect `type -a opencode opencode2`, versions, and both help surfaces.

OpenCode v1 supports an interactive launch with pinned `--model`, `--agent`, and `--auto`. The currently supported OpenCode 2 default TUI does not emit the configured model or agent from an Alera Managed profile; its `mini` and `run` modes have different lifecycle and approval behavior. Use v1 when the profile must pin different models unless current CLI evidence proves v2 gained an equivalent interactive contract.

### Antigravity

Effort support is model-specific. A Gemini profile may accept `--effort high` while a Claude model rejects any effort flag. Probe the exact model and omit `effort` when its CLI says the option is unsupported. A successful response from a fallback model is still a failed model-selection test.

### Cursor

Cursor model ids can encode effort. Discover them with the installed CLI instead of composing slugs.

Cursor status uses Alera-managed entries in `~/.cursor/hooks.json`. If the terminal answers but `agentType` is absent, confirm that file contains the Alera-marked commands and that `GROK_CURSOR_HOOKS_ENABLED=false` is set so a Grok turn cannot steal the identity. Report a missing hook file as a status integration failure, not as a missing tab or failed model launch.

For requested smoke tests, read [launch validation](launch-validation.md).
