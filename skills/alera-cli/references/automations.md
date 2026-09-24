# Automations

## Automations

`alera automation` operates the same catalog as desktop and mobile. List, show, create, edit, approve, pause, resume, trash, restore, purge, run-now, runs, lifecycle, templates, tags, import, export, and policy all go through the authenticated runtime host.

Scheduled and manual execution still require `[automation] declared = true` in the workspace or project `alera.toml`. Draft create, edit, trash, restore, and approve do not. Agent profile `mayExecute` is a separate policy.

```bash
alera automation list
alera automation --json show --id <automation-id>
alera automation create --file definition.json
alera automation approve --id <automation-id> --revision <revision>
alera automation run-now --id <automation-id> --skip-precheck --overlap skip
alera automation templates
alera automation policy --kind show --profile-id <profile-id>
```

Existing-tab JSON targets need `workspaceId` and `tabId`. `conversationId` is optional when saving. Existing-tab execution still requires a conversation ID whose continuity can be verified.
