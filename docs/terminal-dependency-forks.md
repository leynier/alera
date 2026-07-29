# Terminal dependency forks

Alera keeps terminal dependency fixes reproducible through submodules while the fixes are released from maintained forks or reviewed upstream.

The `ghostty_vte` package names remain owned and published by the upstream project on pub.dev. Alera consumes the maintained fork only through the path overrides in `pubspec.yaml`; the fork's GitHub releases supply the matching native artifacts.

## Pattern

- Create a fork under `leynier/*`.
- Apply the minimal fix on a named branch.
- Open a pull request from that branch to the upstream repository.
- Add the fork branch as a submodule under `third_party/`.
- Point `dependency_overrides` at the package path inside the submodule.

## Current forks

| Package | Submodule | Fork branch | Upstream PR |
| --- | --- | --- | --- |
| `ghostty_vte` | `third_party/dart_terminal` | `master` | <https://github.com/kingwill101/dart_terminal/pull/15> |
| `xterm` | `third_party/xterm` | `next` | See `third_party/xterm/ALERA_PATCHES.md` |
