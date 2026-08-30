# Terminal dependency forks

Alera pins terminal dependency fixes through submodules. Each maintained fork has two permanent remote branches: `next` is the default and holds our validated changes; `master` exactly mirrors the upstream default branch. Temporary pull-request branches are deleted after merge, while both permanent branches are protected against deletion.

The `ghostty_vte` package names remain owned and published by the upstream project on pub.dev. Alera consumes the maintained fork only through the path overrides in `pubspec.yaml`; the fork's GitHub releases supply the matching native artifacts.

## Pattern

- Create a fork under `leynier/*`.
- Apply the minimal fix with a regression test and record its upstream relationship in `ALERA_PATCHES.md`.
- Keep validated changes on `next`; propose upstream changes separately when appropriate.
- Match the upstream default branch name for the mirror (`master` for all three current forks). Select that branch explicitly when using GitHub Sync Fork, or run `gh repo sync leynier/<fork> --branch master`. Never apply fork-specific commits to the mirror. Review upstream integration into `next` separately; syncing the mirror does not update Alera's dependency pin.
- Add the fork as a submodule under `third_party/`, with `branch = next` and a committed, tested gitlink SHA.
- Point `dependency_overrides` at the package path inside the submodule.
- Before consolidating branches, preserve their refs in a verified Git bundle and prove that their changes are integrated. Do not remove tags or releases.

## Current forks

| Package | Submodule | Fork branch | Notes |
| --- | --- | --- | --- |
| `ghostty_vte` | `third_party/dart_terminal` | `leynier/dart_terminal:next` | Existing SDK, bindings and native artifacts retained; upstream upgrade deferred |
| `xterm2` | `third_party/xterm` | `leynier/xterm2:next` | Desktop and mobile renderer; see `third_party/xterm/ALERA_PATCHES.md` |

`leynier/xterm.dart:next` retains the complete legacy fork history. It remains available and is not archived, but Alera no longer depends on it. The old upstream proposals [xterm.dart #227](https://github.com/TerminalStudio/xterm.dart/pull/227) and [dart_terminal #15](https://github.com/kingwill101/dart_terminal/pull/15) were closed without merging; their fork fixes are retained locally.

The inherited `autotag.yml` workflow is disabled in both xterm forks so a mirror sync cannot create tags. Fork-owned build and asset-hash updates target `next`. The `dart_terminal:master` mirror can contain a newer SDK than Alera supports; upgrading `next` remains a separate decision.

See [the migration validation report](xterm2-migration-validation.md) and [branch preservation manifest](terminal-fork-branches.json) for the audited bases, conservation evidence, validation and recovery details.
