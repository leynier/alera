# Terminal dependency forks

Alera keeps terminal dependency fixes local through submodules while the fixes are reviewed upstream.

## Pattern

- Create a fork under `leynier/*`.
- Apply the minimal fix on a named branch.
- Open a pull request from that branch to the upstream repository.
- Add the fork branch as a submodule under `third_party/`.
- Point `dependency_overrides` at the package path inside the submodule.

## Current forks

| Package | Submodule | Fork branch | Upstream PR |
| --- | --- | --- | --- |
| `ghostty_vte` | `third_party/dart_terminal` | `fix/puro-pub-cache-detection` | <https://github.com/kingwill101/dart_terminal/pull/15> |
| `xterm` | `third_party/xterm` | `next` | See `third_party/xterm/ALERA_PATCHES.md` |
