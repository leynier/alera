# antigravity provider

This crate adapts the configured Antigravity ACP executable to the shared Rust provider contract through `alera-provider-acp`.

Launch, authentication, profile isolation, permission modes, and resume behavior follow the development reference at [reference_projects/t3code](../../reference_projects/t3code), whose revision is recorded by the repository gitlink, primarily `apps/server/src/provider/Drivers/AntigravityDriver.ts`, `provider/antigravityAuthSupport.ts`, `provider/acp/AntigravityAcpSupport.ts`, and `AntigravityProtocol.ts`. Profile launches set `GEMINI_HOME`, `AGY_ACP_FORCE_FILE_STORAGE`, and an isolated temporary directory with explicit environment overrides preserved.

The crate does not bundle or copy the proprietary host. The executable, working directory, profile path, and environment are configurable; ACP wire handling remains in the shared Rust client/runtime.
