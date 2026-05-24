# AGENTS

## Scope

This file applies to release scripts, packaging helpers, updater manifest generation, and release verification code under `tool/release/`.

## Release Policy

- GitHub Releases are the source of public desktop distribution in v1.
- Tags use `vX.Y.Z` for stable releases and `vX.Y.Z-rc.N` for release candidates.
- Do not publish a stable release if any platform artifact or update archive is missing.
- Keep release scripts deterministic and testable outside GitHub Actions where practical.

## Updater Policy

- Alera uses `desktop_updater` behind an internal app-owned updater boundary.
- UI and controllers must depend on Alera updater abstractions, not directly on `desktop_updater`.
- The stable public update index is `app-archive.json`.
- The release-candidate public update index is `app-archive-rc.json`.
- Stable auto-install is disabled until trusted signing/notarization is available for the release build.
- Unsigned stable builds may show that an update exists and open the manual download page.
- RC or preview auto-install may be enabled only by explicit build flags.

## Signing Policy

- macOS production auto-update requires Apple Developer ID signing and notarization.
- Windows production auto-update requires Authenticode signing.
- Linux artifacts must document package/dependency expectations.
- Signing secrets must never be required by local manifest-generation scripts.
