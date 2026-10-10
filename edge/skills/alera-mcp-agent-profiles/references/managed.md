# Managed Configuration

A managed profile stores its settings in `managedConfig`, and Alera builds the command line from them. These are the keys of Alera's current adapters. Unknown keys fail closed, and `show_agent_profile` returns an existing configuration in the same shape.

| Adapter | Keys |
|---|---|
| `codex` | `model`, `effort`, `planModeEffort`, `sandbox`, `approvalPolicy`, `webSearch`, `bypassApprovalsAndSandbox` |
| `claude` | `model`, `effort`, `agent`, `permissionMode`, `allowSkipPermissions`, `ccsProfile` |
| `copilot` | `model`, `effort`, `agent`, `mode`, `context`, `allowAll`, `maxAiCredits`, `maxAutopilotContinues`, `noAskUser` |
| `cursor` | `model`, `mode`, `permissionMode`, `sandbox`, `trustWorkspace` |
| `agy` | `model`, `effort`, `agent`, `mode`, `skipPermissions`, `sandbox` |
| `opencode` | `model`, `agent`, `autoApprove` |
| `opencode2` | `model`, `agent`, `autoApprove` |
| `pi` | `model`, `thinking`, `projectTrust` |
| `amp` | `mode`, `fast` |
| `grok` | `model`, `effort`, `agent`, `permissionMode`, `sandbox`, `disableWebSearch` |
| `fx` | `resumeLast`, `noAdditionalDirs`, `record` |

Use model names the user actually has; never invent a model slug. `quotaGroup` marks profiles that draw from the same usage limit, and `description` says what the profile is for. Coordinators read both to choose profiles and fallbacks, so keep them accurate.

Example of a managed Codex profile:

```json
{
  "name": "Codex High",
  "agentType": "codex",
  "launchMode": "managed",
  "managedConfig": {"model": "gpt-5.6-sol", "effort": "high", "webSearch": true},
  "description": "Hard implementation and deep debugging.",
  "quotaGroup": "codex"
}
```

The model in the example is illustrative.
