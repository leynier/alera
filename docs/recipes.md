# Recipes

A recipe is the template of an isolated [run](runs.md): versioned, portable coordinator instructions, roles and mandatory stages, with embedded [role contracts](orchestration-role-contracts.md). New Run (desktop and mobile) shows it as **Template**, and `alera orchestration run new --template` selects it. Catalog operations never create runs, tasks, worktrees or workers; plan approval, execution, stage gates and integration are run operations, not capabilities granted by importing a recipe. Shared runs do not use recipes.

## Origins And Identity

The catalog always includes Built-in and Personal recipes. An explicitly selected, active local workspace of a Git project also contributes Project recipes from that workspace's `.alera/workflows/*.yaml`. This reads the selected checkout, not whichever workspace is active in the desktop. Folder projects, remote workspaces and removed workspaces are rejected.

Origins never override one another. A Personal recipe named Quick Fix can coexist with the Built-in Quick Fix and a Project Quick Fix. Selection uses an explicit source object, never an unqualified name:

| Origin | Source identity | CLI shorthand |
| --- | --- | --- |
| Built-in | `{"origin":"builtIn","id":"quick-fix"}` | `builtIn:quick-fix` |
| Personal | `{"origin":"personal","id":"quick-fix"}` | `personal:quick-fix` |
| Project | `{"origin":"project","workspaceId":"<id>","path":".alera/workflows/quick-fix.yaml"}` | `project:.alera/workflows/quick-fix.yaml` (workspace from `--workspace`) |

Project filenames distinguish otherwise identical recipe ids within a checkout. Invalid files stay visible with diagnostics. An unavailable project directory reports a catalog-level error without hiding Built-in and Personal entries. Built-ins and project files are read-only through this API. Personal recipes live in the runtime database (`personalRecipes`) and survive orchestration resets, the [schema v3 reset](runs.md#upgrading-to-schema-v3) and runtime restarts.

## Built-in Recipes

The sources are under `rust/alera-core/src/runtime/recipes/`:

- [Freeform](../rust/alera-core/src/runtime/recipes/freeform.yaml): one stage, one Worker role, no stage gates. It is the default template of an isolated run.
- [Quick Fix](../rust/alera-core/src/runtime/recipes/quick-fix.yaml): Fix and Verify stages.
- [Feature Delivery](../rust/alera-core/src/runtime/recipes/feature-delivery.yaml): Foundation, Implementation and Product stages, with human Foundation and Product gates.

No recipe selects an agent provider or model; New Run binds each role to an Agent Profile (unbound roles use the worker profile, or the coordinator's).

## Portable Format

A version 1 recipe requires `version`, `id`, positive `revision`, `name`, `description`, `coordinatorInstructions`, `contracts`, `roles` and `stages`. It carries its own versioned contract definitions. Roles reference an exact `contractId` and `contractRevision` within the same recipe; there are no remote or cross-catalog contract dependencies. Agent Profile bindings, commands, credentials and local identifiers are separate from the portable document. Free-text instructions are user content, not a credential store: do not put secrets in them.

Every declared stage is mandatory. Each has an id, name, purpose, non-empty role-id list and explicit `dependsOn` list. The coordinator proposes concrete tasks within these constraints; a recipe is not an executable task DAG. Compilation rejects duplicate ids, missing role, contract or dependency references, mismatched contract revisions, unused roles or contracts, self-dependencies and cycles. A stage's optional `gate` is `foundation` or `product`; each kind can occur at most once, a Product gate must depend transitively on every other stage, and both always open a `stage` gate a person resolves.

The compiler also validates every embedded role contract, its bounded schemas and its portable artifact paths. Unknown fields, executable hooks, includes, profile commands, aliases, anchors, YAML tags and merge keys are rejected. Instructions can describe agent work, but importing or validating them never runs a command.

## Limits And File Safety

- One UTF-8 YAML mapping document, at most 256 KiB, 8,192 YAML nodes and nesting below 24 levels. Typed recipe and contract JSON validation applies its additional 4,096-node and depth limits.
- Between 1 and 16 contracts, roles and stages. Recipe and role names are at most 160 bytes, descriptions and stage purposes 4 KiB, and coordinator instructions 16 KiB.
- At most 128 Personal recipes and 128 Project YAML files. Project directory enumeration stops at 2,048 entries; successfully read project documents total at most 8 MiB.
- Only direct, lowercase `.yaml` files are read. No recursive discovery, `.yml` aliases, symlink traversal or special files. Directory capabilities and no-follow opens preserve the boundary while paths change, and reads stay bounded even if a file grows.
- Plain `true`, `false`, `null`, `~` and JSON numbers use their scalar types. Other plain values, including `yes`, remain strings. Quoted and block values remain strings. Duplicate mapping keys and non-string keys are rejected.

Canonical export is JSON, which is valid YAML, formatted when it fits the document limit and compact otherwise. It contains only the validated portable definition, without comments or original formatting. Snapshot digests use canonical key ordering and include the explicit source and the complete recipe and contracts. `runs.create` freezes the recipe snapshot, so later catalog edits cannot change an existing run.

Filesystem reads, parsing and compilation run in a bounded blocking pool outside the runtime actor. Catalog requests have a bounded queue and deadline; listing returns summaries, with full recipe detail requested separately. Opening the catalog starts no polling, watcher or worker.

## CLI And RPC

```bash
alera orchestration --json recipe list --workspace <workspace-id>
alera orchestration --json recipe show --source '{"origin":"builtIn","id":"quick-fix"}'
alera orchestration --json recipe validate --stdin < recipe.yaml
alera orchestration --json recipe save-personal --stdin < recipe.yaml
alera orchestration --json recipe save-personal --expected-revision 1 --stdin < edited-recipe.yaml
alera orchestration --json recipe export --workspace-id <workspace-id> --filename release.yaml --stdin < recipe.yaml
alera orchestration --json recipe export --workspace-id <workspace-id> --filename release.yaml --expected-digest <digest> --apply --stdin < recipe.yaml
```

On PowerShell, pipe `Get-Content -Raw recipe.yaml` into a command that uses `--stdin`. `--document '<YAML text>'` is the alternative, mutually exclusive with stdin. Show returns the source, document digest, catalog revision where applicable, and the portable `recipe` definition. To copy a Built-in or Project recipe to Personal, submit only that definition to Save Personal. A same-id Personal recipe is never overwritten without its expected catalog revision. The recipe `revision` belongs to the portable definition; the catalog revision is a separate, runtime-owned, monotonically increasing edit token.

| Verb | CLI | Clients |
| --- | --- | --- |
| `recipes.catalog {workspaceId?}` | `recipe list` | Local and mobile |
| `recipes.recipe {source}` | `recipe show` | Local and mobile |
| `recipes.validate {document}` | `recipe validate` | Local only |
| `recipes.savePersonal {document, expectedRevision?}` | `recipe save-personal` | Local only |
| `recipes.previewExport`, `recipes.applyExport` | `recipe export`, `recipe export --apply` | Local only |

The capability is `recipesV1`, advertised in the control file, `status.get` and `MOBILE_HELLO_CAPABILITIES`; without it clients show Update Required and the CLI asks for a restart. Requests reject unknown fields and never trust an `actor` field.

Personal writes use a transactional compare-and-swap. Omit `expectedRevision` only for a new id; updates require the current revision. A stale or duplicate create fails without changing the stored record. After a successful save, every authenticated client receives `recipesChanged {source, catalogRevision}`. A timed-out save has an uncertain outcome: refresh the recipe before retrying instead of assuming failure or overwriting a newer edit.

## Settings And Reviewed Export

**Settings > Recipes** presents the catalog with explicit origins, search and a project workspace selector; selecting a workspace there does not switch the active workspace. New Run links to it with **Manage Recipes**. Built-in and Project recipes can be copied with **Copy To Personal**; Personal recipes can be edited with their role contracts (**Edit Personal**), checked with **Validate** and stored with **Save Personal**. Editing keeps the recipe's identity; use Copy To Personal to choose a new id. A draft survives navigation between Settings sections within the current desktop session. Project entries offer **Open File**, including invalid recipes that need repair. The pane refreshes on demand (**Refresh Catalog**).

After a stale or uncertain save, **Review Current Recipe** compares the runtime's current Personal version with the retained draft. Matching content confirms the save without repeating it. Otherwise **Keep My Draft** adopts only the reviewed catalog revision, leaving Save Personal as a separate explicit write, and **Use Current Version** replaces the draft. Concurrent updates after review still fail the revision check. Copy recovery looks up the candidate id in the draft, never in the source recipe, and an absent candidate keeps create-only semantics.

**Export To Project** writes a recipe into a workspace's `.alera/workflows/`. `recipes.previewExport` takes `workspaceId`, a portable `filename` and `document`, and returns the relative destination, the previous text, the canonical exported text and `expectedDigest`, without creating directories or files. Settings shows the destination and a line diff (**Review Export**, **Confirm Export**). `recipes.applyExport` requires that digest and the same destination and document; the digest binds the workspace instance, path, prior bytes and exported definition, so a change since the preview needs another review.

Writes stay in the bounded Rust catalog pool. New files are published without overwriting a concurrent create. Replacing a reviewed file keeps its previous inode in a uniquely named `.export-retained-*.bak` sibling, which allows recovery and preserves edits through open editor handles; the response and success message report that path. Retained files are not recipes and are not cleaned automatically. On a race or interruption, inspect the destination and the retained file before retrying. Filesystems without hard-link support reject publication and keep any displaced original for recovery.
