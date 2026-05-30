# AGENTS

## Scope

This file applies to GitHub metadata and GitHub Actions workflows.

## Workflow Policy

- Release jobs must be reproducible from a clean checkout.
- Build jobs must run on native runners for their platform.
- Any job that builds the desktop app or runs the Linux desktop integration tests must set up the pinned Rust toolchain (matching `rust/rust-toolchain.toml`) and the Rust build cache before the Flutter build, because the native build hooks compile the Rust `alera` terminal-host sidecar via `cargo build --locked`. Keep this consistent across `pr.yml`, `desktop-build.yml`, and `release-cut.yml`.
- Pull request workflows must initialize required submodules before dependency resolution.
- Do not expose partial releases to users.
- Release automation must publish drafts first, verify required assets and update manifests, then publish public releases.
- Release workflows must not push release commits or tags until platform artifacts and update manifests have been generated and verified.
- Update indexes must be deployed only after the corresponding GitHub Release is public.
- Existing stable and release-candidate update indexes must be preserved when publishing the other channel; ignore only confirmed first-time 404 responses.
- Stable release jobs must not enable automatic installation until signing and notarization or trust are configured for the relevant platform.
- Signing secrets must be scoped only to release jobs that need them.

## Issue And PR Policy

- Issue templates should collect platform details when behavior may differ across macOS, Windows, and Linux.
- Pull request templates should require validation notes, platform notes, and security/update risk notes when relevant.
- Workflow-created labels must be created idempotently when they may not exist in a fresh public repository.
