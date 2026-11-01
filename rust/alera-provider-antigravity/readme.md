# antigravity provider

This crate adapts the configured Antigravity ACP executable to the shared Rust provider contract through `alera-provider-acp`.

Launch, authentication, profile isolation, permission modes, and resume behavior follow the development reference at [reference_projects/t3code](../../reference_projects/t3code), whose revision is recorded by the repository gitlink, primarily `apps/server/src/provider/Drivers/AntigravityDriver.ts`, `provider/antigravityAuthSupport.ts`, `provider/acp/AntigravityAcpSupport.ts`, and `AntigravityProtocol.ts`. Profile launches set `GEMINI_HOME`, `AGY_ACP_FORCE_FILE_STORAGE`, and an isolated temporary directory with explicit environment overrides preserved.

The crate does not bundle or copy the proprietary host. The executable, working directory, profile path, and environment are configurable; ACP wire handling remains in the shared Rust client/runtime.

# Questions

Antigravity asks a question through `session/request_permission` with a `toolCall.toolCallId` of `interaction_*`, and its options are answers rather than approvals. As in T3 Code's `AntigravityProtocol.ts`, such a request with unique, non-blank `optionId`s opens one single-choice question (`allowCustomAnswer: false`) with the tool call's title (cut to 8000 characters) and the option names as labels (cut to 512). The answer is sent as the selected `optionId`; a label only one option carries resolves to its id, Skip (no answers) and Stop answer `cancelled`, and any other answer is refused while the question stays open. An approval cannot answer it. A malformed interaction, and every other agent's permission request, stays an approval.

# Client Identity

The adapter identifies as Zed (`clientInfo` and `info` `{"name":"zed","version":"0.0.0"}`, `ANTIGRAVITY_CLIENT_NAME` and `ANTIGRAVITY_CLIENT_VERSION`), as T3 Code's `AntigravityAcpSupport.ts` does, because the Antigravity ACP runtime offers its Claude and GPT models only to allowlisted clients such as Zed; under Alera's own name it offers only Gemini models. Grok and the ACP registry keep identifying as `alera`. Client file reads and writes stay off (`fs.readTextFile` and `fs.writeTextFile` false), so the agent keeps its native diff edits instead of whole-file client writes.

Risk: this impersonates another client. Google may treat it as a breach of the Antigravity terms of service, close the allowlist to unofficial clients, or change what a `zed` client receives, and the account that signs in carries that risk. Change the constants to stop impersonating; the runtime then offers only its Gemini models.
