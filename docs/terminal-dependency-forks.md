# Terminal dependency forks

Alera pins terminal dependency fixes through submodules. Each maintained fork has `next` as its default and only permanent remote branch; changes land there after validation, and temporary pull-request branches are deleted after merge.

The `ghostty_vte` package names remain owned and published by the upstream project on pub.dev. Alera consumes the maintained fork only through the path overrides in `pubspec.yaml`; the fork's GitHub releases supply the matching native artifacts.

## Pattern

- Create a fork under `leynier/*`.
- Apply the minimal fix with a regression test and record its upstream relationship in `ALERA_PATCHES.md`.
- Keep validated changes on `next`; propose upstream changes separately when appropriate.
- Add the fork as a submodule under `third_party/`, with `branch = next` and a committed, tested gitlink SHA.
- Point `dependency_overrides` at the package path inside the submodule.
- Before consolidating branches, preserve their refs in a verified Git bundle and prove that their changes are integrated. Do not remove tags or releases.

## Current forks

| Package | Submodule | Fork branch | Notes |
| --- | --- | --- | --- |
| `ghostty_vte` | `third_party/dart_terminal` | `leynier/dart_terminal:next` | Existing SDK, bindings and native artifacts retained; upstream upgrade deferred |
| `xterm2` | `third_party/xterm` | `leynier/xterm2:next` | Desktop and mobile renderer; see `third_party/xterm/ALERA_PATCHES.md` |

`leynier/xterm.dart:next` retains the complete legacy fork history. It remains available and is not archived, but Alera no longer depends on it. The old upstream proposals [xterm.dart #227](https://github.com/TerminalStudio/xterm.dart/pull/227) and [dart_terminal #15](https://github.com/kingwill101/dart_terminal/pull/15) were closed without merging; their fork fixes are retained locally.

See [the migration validation report](xterm2-migration-validation.md) and [branch preservation manifest](terminal-fork-branches.json) for the audited bases, conservation evidence, validation and recovery details.
