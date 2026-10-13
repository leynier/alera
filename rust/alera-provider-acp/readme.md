# Upstream

This crate ports the provider-facing ACP adapter boundary from [reference_projects/t3code](../../reference_projects/t3code). The repository gitlink records the development reference revision. The relevant source is `packages/provider-acp/src/server/adapter.ts` and its runtime/event helpers. The wire client is ported separately in `agent-client-protocol` from `packages/effect-acp`.

The upstream ACP declarations and adapter-facing client are MIT-licensed. This crate retains this provenance and keeps unknown ACP payloads in raw event fields. Vendor-specific executables remain external dependencies of wrappers.
