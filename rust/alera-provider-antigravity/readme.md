# antigravity provider

This crate adapts the configured Antigravity ACP executable to the shared Rust provider contract through `alera-provider-acp`.

Launch, authentication, profile isolation, permission modes, and resume behavior follow the development reference at [reference_projects/t3code](../../reference_projects/t3code), whose revision is recorded by the repository gitlink, primarily `apps/server/src/provider/Drivers/AntigravityDriver.ts`, `provider/antigravityAuthSupport.ts`, `provider/acp/AntigravityAcpSupport.ts`, and `AntigravityProtocol.ts`. Profile launches set `GEMINI_HOME`, `AGY_ACP_FORCE_FILE_STORAGE`, and an isolated temporary directory with explicit environment overrides preserved.

The crate does not bundle or copy the proprietary host. The executable, working directory, profile path, and environment are configurable; ACP wire handling remains in the shared Rust client/runtime.

# Questions

Antigravity asks a question through `session/request_permission` with a `toolCall.toolCallId` of `interaction_*`, and its options are answers rather than approvals. As in T3 Code's `AntigravityProtocol.ts`, such a request with unique, non-blank `optionId`s opens one single-choice question (`allowCustomAnswer: false`) with the tool call's title (cut to 8000 characters) and the option names as labels (cut to 512). The answer is sent as the selected `optionId`; a label only one option carries resolves to its id, Skip (no answers) and Stop answer `cancelled`, and any other answer is refused while the question stays open. An approval cannot answer it. A malformed interaction, and every other agent's permission request, stays an approval.
