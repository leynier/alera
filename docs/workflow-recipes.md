# Workflow Recipe Catalogs

Recipes are versioned, portable orchestration instructions, roles and mandatory stages. They reuse [role contracts](orchestration-role-contracts.md) and the Rust runtime. Catalog operations do not create runs, tasks, worktrees or workers. Plan approval, execution, stage-gate enforcement and integration are separate runtime operations, not capabilities granted by importing a recipe.

## Origins And Identity

The catalog always includes Built-in and Personal recipes. An explicitly selected, active local workspace of a Git project also contributes Project recipes from that workspace's `.alera/workflows/*.yaml`. This reads the selected checkout, not whichever workspace happens to be active in the desktop. Folder projects, remote workspaces and removed workspaces are rejected.

Origins never override one another. A Personal recipe named Quick Fix can coexist with the Built-in Quick Fix and a Project Quick Fix. Selection uses an explicit source object, never an unqualified name:

| Origin | Source identity |
| --- | --- |
| Built-in | `{"origin":"builtIn","id":"quick-fix"}` |
| Personal | `{"origin":"personal","id":"quick-fix"}` |
| Project | `{"origin":"project","workspaceId":"<id>","path":".alera/workflows/quick-fix.yaml"}` |

Project filenames distinguish otherwise identical recipe ids within a checkout. Invalid files remain visible with diagnostics. An unavailable project directory reports a catalog-level error without hiding Built-in and Personal entries. Built-ins and project files are read-only through this API. Personal records live in the runtime database and survive orchestration task/message resets and runtime restarts.

## Portable Format

The complete initial examples are [Quick Fix](../rust/alera-core/src/runtime/workflows/quick-fix.yaml) and [Feature Delivery](../rust/alera-core/src/runtime/workflows/feature-delivery.yaml). Quick Fix has Fix and Verify stages. Feature Delivery has Foundation, Implementation and Product stages, with explicitly human Foundation and Product gates. Neither recipe selects an agent provider or model.

A version-1 recipe requires `version`, `id`, positive `revision`, `name`, `description`, `coordinatorInstructions`, `contracts`, `roles` and `stages`. It contains its own versioned contract definitions. Roles reference an exact `contractId` and `contractRevision` within the same recipe; there are no remote or cross-catalog contract dependencies. Copying a recipe explicitly copies these definitions. Agent Profile bindings and their commands, credentials and local identifiers are separate from the portable document. Free-text instructions are user content, not a credential store: do not place secrets in them.

Every declared stage is mandatory. Each has an id, name, purpose, nonempty role-id list and explicit `dependsOn` list. The coordinator can later propose concrete tasks within these constraints; a recipe is not an executable task DAG. Compilation rejects duplicate ids, missing role/contract/dependency references, mismatched contract revisions, unused roles/contracts, self-dependencies and cycles. A stage's optional `gate` is `foundation` or `product`; neither has an automatic variant. Each kind can occur at most once. A Product gate must depend transitively on all other stages.

The compiler also validates every embedded role contract, its bounded schemas and portable artifact paths. Unknown fields, executable hooks, includes, profile commands, aliases, anchors, YAML tags and merge keys are rejected. Instructions can describe agent work, but importing or validating them never runs a command.

## Limits And File Safety

- One UTF-8 YAML mapping document, at most 256 KiB, 8,192 YAML nodes and nesting below 24 levels. Typed recipe/contract JSON validation applies its additional 4,096-node and depth limits.
- Between 1 and 16 contracts, roles and stages. Recipe and role names are at most 160 bytes, descriptions/stage purposes 4 KiB, and coordinator instructions 16 KiB.
- At most 128 Personal recipes and 128 Project YAML files. Project directory enumeration stops at 2,048 entries; successfully read project documents total at most 8 MiB.
- Only direct, lowercase `.yaml` files are read. No recursive discovery, `.yml` aliases, symlink traversal or special files. Directory capabilities and no-follow opens preserve the boundary while paths change. Reads are bounded even if a file grows.
- Plain `true`, `false`, `null`, `~` and JSON numbers use their corresponding scalar types. Other plain values, including `yes`, remain strings. Quoted and block values remain strings. Duplicate mapping keys and non-string keys are rejected.

Canonical export is JSON, which is valid YAML, formatted when it fits the document limit and compact otherwise. It contains only the validated portable definition. It does not preserve comments or original YAML formatting. Snapshot digests use canonical object-key ordering and include the explicit source and complete recipe/contracts. Later catalog edits cannot mutate an already-created snapshot.

Filesystem reads, parsing and compilation run in a bounded blocking pool outside the runtime actor. A blocking job retains its permit if its caller times out. Catalog RPCs have a bounded queue and deadline; listing returns summaries, with full recipe detail requested separately. No background polling, filesystem watcher or worker is started by opening the catalog.

## CLI And RPC

```bash
alera orchestration --json recipes list --workspace <workspace-id>
alera orchestration --json recipes show --source '{"origin":"builtIn","id":"quick-fix"}'
alera orchestration --json recipes validate --stdin < recipe.yaml
alera orchestration --json recipes save-personal --stdin < recipe.yaml
alera orchestration --json recipes save-personal --expected-revision 1 --stdin < edited-recipe.yaml
```

On PowerShell, pipe `Get-Content -Raw recipe.yaml` into a command using `--stdin`. `--document '<YAML text>'` is an alternative input, mutually exclusive with stdin. Show returns the source, document digest, catalog revision where applicable, and portable `recipe` definition. To copy a Built-in or Project recipe to Personal, submit only that definition to Save Personal. A same-id Personal recipe is never overwritten without its expected catalog revision. Recipe revision belongs to the portable definition; catalog revision is a separate, runtime-owned monotonically increasing edit token.

The additive `workflowRecipeCatalogV1` capability advertises `workflows.catalog`, `workflows.recipe`, `workflows.validateRecipe` and `workflows.savePersonalRecipe`. These RPCs accept authenticated local clients only and reject unknown request fields. They do not trust an `actor` field. Catalog support does not advertise workflow execution support, and strict terminal-host/orchestration versions remain unchanged. The CLI requires the catalog capability; an older host cannot fall back to legacy execution or shared workspaces.

Personal writes use a transactional compare-and-swap. Omit `expectedRevision` only for a new id; updates require the current revision. A stale or duplicate create fails without changing the stored record. After a successful save, authenticated local clients receive `workflowCatalogChanged` with source and catalog revision. A timed-out save has an uncertain outcome: refresh the recipe before retrying, rather than assuming failure or overwriting a newer edit. Project file export and its destination/diff/concurrency review are not part of this catalog-write API.
