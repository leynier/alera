# Muse agent SDK

Rust client for the public Muse Session Protocol surface used by the provider adapter. It implements bounded JSON-RPC framing, handshake ordering, command replay protection, server request correlation, and a version-aware session state fold over `alera-agent-transport`.

The port follows `@muse-code/sdk` 1.4.6 from `meta-models/muse-code-sdk` at commit `ea88c8221d381de7cb28281be8bc6b8b1507ba72`. The upstream SDK and committed protocol declarations are MIT licensed; this crate retains the accompanying MIT notice in `LICENSE`. The `muse` host executable is not included in the upstream source tree or npm artifact, so it remains an external runtime dependency with separate licensing.
