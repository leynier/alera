# Provider Protocol

This crate defines a UI-independent provider lifecycle and normalized runtime events. The development contract reference is [reference_projects/t3code](../../reference_projects/t3code), particularly `packages/contracts/src/providerRuntime.ts`, `providerPolicy.ts`, and `packages/provider-core/src/server/ProviderAdapter.ts`. Reference files are not runtime dependencies.

The standalone boundary keeps caller-owned thread identities separate from native provider references. An application integration must allocate and map application-owned turn, item and request identities before persisting events in an orchestration store. Unknown provider kinds, event names and raw messages remain available for forward compatibility.

The required upstream MIT copyright notice is preserved in `LICENSE`.
