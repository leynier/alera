# Claude Web Plugin Plan

## Spec

Provide an independent Alera plugin upload for Claude web with five skills, remote MCP, OAuth discovery, metadata, logo, and static downloads. Preserve the existing ChatGPT package byte for byte. Do not change authentication grants, credentials, runtime permissions, or server code. Installing the package must not be described as connecting or authorizing the service.

## Design

Use `landing/claude-plugin/` for Claude-only manifest, MCP configuration, README, and setup skill. Build a deterministic ZIP and identical `.plugin` alias from an explicit allowlist and the existing MCP skill catalog, adapting reference-loading instructions for Claude's bundled skills. Use fixed public HTTP MCP URL and server-discovered OAuth; no client credentials or Code-only OAuth overrides. Publish both archives and separate checksums in the static landing build and CI artifacts.

## Tasks

- [x] Verify official web, manifest, upload, and OAuth documentation and inspect PR #932 and its existing watch.
- [x] Implement the independent package and web downloads.
- [x] Verify archive constraints, skill adaptations, original ZIP preservation, and desktop/mobile downloads.
- [x] Ship changes through PR #932 and retain its existing Watch, Fix and Merge session.

Delivery-time CI, review fixes, and merge verification are tracked by the runtime watch and `build/claude-plugin/delivery-tracker.md`; real Claude account authorization is outside package validation.

## Tests And Assumptions

Run landing unit tests, typecheck, production build, and Playwright. Verify both extensions decode as identical archives, manifest and resource paths exist, supported upload limits are satisfied, no secrets or local components are bundled, and the ChatGPT ZIP retains SHA-256 `4f1fedc3116746ebdc0dc006bab198520bc205660b0fb6242bd0f80305811b91`. Public OAuth metadata can be inspected without creating grants. Claude web account upload, connector consent, token exchange, and real runtime calls remain separate manual checks and must not be claimed from archive or CLI validation.
