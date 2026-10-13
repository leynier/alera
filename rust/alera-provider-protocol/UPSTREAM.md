# T3 Code Protocol Provenance

The provider lifecycle and normalized runtime vocabulary are derived from the MIT-licensed T3 Code project, https://github.com/pingdotgg/t3code, pinned at `5d6e4192bfcf9eca09741605e12c72b5970025e4` in `reference_projects/t3code`.

Primary references are `packages/contracts/src/providerRuntime.ts`, `providerPolicy.ts`, `provider.ts`, and `packages/provider-core/src/server/ProviderAdapter.ts`. This crate defines the standalone provider boundary used by the Rust adapters. It does not claim to port T3's entire application orchestration or persistence schema.

The upstream copyright and MIT license are preserved in `LICENSE-T3`.
