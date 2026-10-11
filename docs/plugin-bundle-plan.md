# Downloadable Plugin Bundle

## Spec

Distribute the existing OAuth-backed Alera MCP and its four maintained MCP skills as one downloadable ZIP. Include listing metadata, the existing Alera logo, a setup skill, and installation instructions. The website must generate the ZIP from the current skill sources and remain static. Do not modify runtime access, deploy the site, or submit to OpenAI as part of this change.

## Design

Keep package metadata and setup instructions under `landing/plugin/`. Build a deterministic archive from those files, `edge/skills/`, and the existing public logo, using an Astro build integration. Include the portable manifest and a generated Codex compatibility manifest. Provide a local marketplace inside the extracted plugin folder for manual installation, and expose the same package through the web download page and a dedicated docs guide.

## Tasks

- [x] Inspect the current MCP, skill sources, website, and official plugin formats.
- [x] Implement the package, onboarding, archive builder, and standalone packaging command.
- [x] Add web download, installation guide, and CI coverage for all package inputs.
- [x] Validate archive integrity, skill preservation, metadata paths, website build, and desktop/mobile behavior.

## Tests

Check deterministic archive bytes; extract the real ZIP and verify every skill/reference against its source; verify the portable and compatibility manifests, onboarding dependency, included assets, and safe package paths. Run landing unit tests, type checking, build, and Playwright. Run the existing MCP skill conformance tests because the package reuses those skills.

Local validation completed: 109 landing unit tests, 60 Playwright tests, 10 MCP skill tests, landing and edge type checks, skill validation, and the static build. After adding the light/dark asset variants, the six archive tests and three plugin browser tests passed again. Codex 0.162.1 installed and enabled the final package in an isolated temporary profile without network access. Desktop and mobile previews were inspected. Production deployment, connected OAuth setup, and public OpenAI submission were not performed.

## Assumptions

The remote endpoint remains `https://api.alera.build/v1/mcp`. Users sign in and choose MCP Control themselves. Manual marketplace installation and the public OpenAI directory are separate distribution paths; public submission and real client OAuth installation require separate verification.
