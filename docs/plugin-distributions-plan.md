# Five Plugin Distributions

## Spec

Deliver five independently downloadable Alera distributions: existing ChatGPT, Claude web, exactly `GrokBot Cursor`, exactly `Agent Plugin`, and GitHub Copilot. Preserve the existing ChatGPT and Claude archive bytes. GitHub Copilot uses an independent Agent Plugins 1.0 package and surface-specific setup; its app requires marketplace availability and no documented logo field is invented. Google and Gemini are excluded. No credentials, authentication grants, persistent permissions, new watchers, or marketplace submissions are authorized by this packaging work.

## Design

Keep client manifests and setup skills separate. Build the third package with `.cursor-plugin/plugin.json`, `mcp.json`, five skills, and the Alera logo. Cursor local folder import is documented; Grok Bot only documents connecting available marketplace plugins, so do not claim this ZIP installs there. Build the fourth package with root `plugin.json`, `mcp.json`, and portable Agent Skills; no client extension data or files. Validate Agent Plugins 1.0.0 with pinned official JSON Schemas and additional semantic checks. OAuth remains client-managed, with no credentials or scope overrides.

## Tasks

- [x] Verify current PR state, preserve the existing fix-and-merge watch, and read official Cursor, Grok Bot, Agent Plugins, and Agent Skills documentation.
- [x] Implement independent reproducible Cursor, pure Agent Plugin, and GitHub Copilot ZIPs, checksums, metadata, skills, and assets where supported.
- [x] Add web downloads, installation guides, independent CI artifacts, and package regression tests.
- [x] Run unit tests, schema validation, type checking, static build, browser tests, and desktop/mobile visual inspection.
- [x] Prepare scoped shipping and preserve the existing watch; track PR state, exact-head CI/reviews, required repairs, merge, and public availability in the delivery tracker.

- [x] Generate and hand off one local-only experimental ZIP with checksum and per-client limits; preserve separate downloads.
- [x] Verify experimental manifest selection and extra-file handling with available local validators, without claiming web/OAuth acceptance.

- [x] Compare the actual Telegram ZIP and standalone OpenAI archive with official desktop-only policy; preserve both MCP packages.
- [x] Document the public ChatGPT web publication workflow, existing-app boundary, preparation blockers, and preliminary user-reported Claude web success.
- [x] Validate the updated web guide; continue scoped shipping through the existing PR/watch in the delivery tracker.

- [x] Show client-specific compatibility/setup before all five ZIP buttons; link this comparison from the existing home Install section, with desktop/mobile visual and browser checks.

## Tests

Assert supported manifest fields, explicit standard transport versus native Cursor URL inference, contained paths, exact skill discovery, string skill metadata, bundled references, authorization rules, absence of credentials and vendor extensions from the portable package, deterministic archives across time zones, all five download endpoints and checksums, accessibility and responsive guides. Pin the original ChatGPT and Claude archive hashes. Validate positive and negative standard manifests and MCP configurations against official draft 2020-12 schemas.

## Delivery Tracking

Implementation and local validation are complete. PR shipping, remote checks, review repair, merge, and production download availability remain tracked in the ignored `build/plugin-distributions/delivery-tracker.md`. The existing watch owns merge. The experimental file was delivered once through the pre-existing private Telegram route; no public download was added.

## Assumptions And Limits

Installation, OAuth, refresh, runtime access, logo rendering, and marketplace availability require separate real-account verification. Agent Plugins does not standardize installation or OAuth. Cursor local installation does not prove Grok Bot installation or account synchronization. Public marketplace publication is outside this change; no undocumented Grok Bot ZIP import is promised. CI artifacts and built website downloads are package evidence, not proof of production deployment.
