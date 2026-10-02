# ChatGPT AI Assist

## Spec

Add ChatGPT as an optional AI Assist provider using OpenAI's open-source Sign in with ChatGPT flow. Users connect, select and disconnect ChatGPT account registrations in desktop AI Assist settings. Credentials belong to the runtime, remain outside synced settings, and never reach paired phones. Existing providers and defaults stay unchanged. ChatGPT generates text from the context Alera supplies, with no local tool execution.

## Design

The runtime owns loopback OAuth with PKCE and OIDC validation, protected credential storage, serialized refresh, account-specific model discovery and cancellable Responses streaming. A new additive capability gates desktop support. The desktop and paired-phone AI Assist paths share inference on the runtime that owns the request. Remote runtimes need their own connection. Account administration is local-client-only.

Credentials are encrypted with ChaCha20-Poly1305 in an atomically replaced runtime file. The system credential store holds only its random encryption key, since a multi-account token record exceeds [Windows Credential Manager's 2560-byte limit](https://learn.microsoft.com/en-us/windows/win32/api/wincred/ns-wincred-credentiala). Linux can fall back to an owner-only file when Secret Service is unavailable. Credential I/O runs outside the server actor. Account changes cancel requests using the previous account; logout retains registration and host identity for reauthorization.

A successful token refresh saves its rotated credentials before fetching signing keys. If a new ID token needs verification, a persisted pending flag blocks inference until that verification succeeds, including after a restart. Temporary key-fetch failures retain the replacement credentials for retry; an identity mismatch clears only the affected registration.

## Tasks

- Completed: implement OAuth, protected registrations, refresh and disconnect.
- Completed: connect Responses inference and model discovery to AI Assist.
- Completed: add desktop account controls and provider selection.
- Completed: regenerate Dart code, normalize generated files, and validate the focused Rust and Flutter suites.
- Completed: Claude Opus Dev reviewed and refined the UI through Alera orchestration (task `task_e42fee33c2a246d1`), including account rows, pending and error states, accessibility and first-use notice.
- Pending manual acceptance: real ChatGPT consent, account eligibility and an AI Assist inference request on a rebuilt runtime.

## Tests

Validate callback state/client binding, signed ID-token issuer/audience/nonce, account isolation, credential permissions, refresh rotation and terminal errors. Verify request shape, catalog visibility/order, cancellation, incomplete/error streams and completion-only success. Check provider serialization, runtime routing and account controls without external inference.

Original SIWC implementation validation: 147 Flutter unit/widget tests, 16 ChatGPT runtime tests, 69 existing AI Assist runtime tests, 3 mobile allowlist tests and 3 shared runtime settings tests. Flutter analysis, Rust Clippy with warnings denied, the 500-line ratchet and whitespace checks passed for that original scope. Tests include discarding a stale model catalog after changing accounts, retaining rotated credentials across a temporary signing-key failure and restart, and clearing only the affected registration on an identity mismatch. No live OAuth or inference call was performed. The later models/options validation is recorded separately below.

## Scope And Sources

The preview supports text chat through Responses with client-managed history. Audio/video input and transcription are explicitly unsupported; this change does not enable dictation or conversational voice. AI Assist may still clean up text that another dictation provider has already transcribed.

- [Registration and sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [Accounts and sessions](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions)
- [Models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
- [Preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)

Real OAuth consent and account eligibility require a browser and a ChatGPT account; mocked local tests do not establish live acceptance.

## Model Catalog, Thinking Effort And Speed Follow-Up

The user explicitly added model discovery, reasoning effort and Normal/Fast selection to the performance/stability PR on 2026-10-02. This work is separate from the second audit findings and remains local; deployment and publication are excluded.

### Spec

Keep model choices account-specific and dynamic, including newly returned slugs without a hardcoded model allowlist. Preserve server visibility and ordering. Refresh after account changes and expose discovery failures instead of presenting an outdated catalog as current. Existing saved models remain distinguishable if unavailable.

Expose model-advertised Responses reasoning levels, preserve global and prompt-specific effort choices, and forward explicit selections to both direct and runtime-configured ChatGPT inference. Do not map Codex-only delegation controls into the tool-free Responses route.

Add a global ChatGPT Speed choice: Normal is the default and Fast is opt-in. Normal selects standard processing; Fast requests faster processing when available and explains that it consumes plan usage faster. Account, model, workspace and regional eligibility remain enforced by OpenAI; errors must stay visible and must not cause an automatic model, provider or tier fallback.

### Design

Keep OAuth credentials entirely runtime-owned. Extend catalog metadata, the injectable host completer and runtime inference without changing the terminal protocol version. Add an options capability so older runtimes cannot silently ignore explicit effort or Fast selection, including the remote satellite that runs configured jobs and speech text cleanup. Resolve effort after choosing the fresh account-default model, since the UI catalog cache is not a runtime model pin. Direct calls with an unresolved model carry only their thinking maps and optional semantic operation, so generic text actions also retain global effort without changing durable runtime settings. Explicit effort wins over that fallback context. Reuse existing per-model and per-operation reasoning settings, with one additive defaulted `chatGptServiceTier` setting for speed.

The current runtime already queries the selected account's live `/v1/models` endpoint. A fixed model list is not the source-level cause of the reported missing GPT-6 models. The initial discovery can fail before account readiness, and the old UI did not retry on the first ready account status. An unknown saved model also hid refresh/error controls behind a text field. Repair these paths and preserve account visibility; local fixtures do not prove the live account is entitled to every requested model.

### Tasks And Acceptance

1. Completed: preserve catalog reasoning metadata and repair evidenced refresh gaps.
2. Completed: carry thinking effort and service tier through direct and configured runtime requests.
3. Completed: add the speed setting, backward-compatible serialization and explicit older-runtime errors.
4. Completed: one-shot generation, EOF normalization, format, full analysis, 248 Flutter regressions and 41 native regressions pass, along with Rust Clippy with warnings denied and the source-line ratchet.
5. Completed: independent review, documented repairs and local commits. Live OAuth/inference acceptance remains unverified.

Validate future model slugs and server order, model-specific supported effort, default settings compatibility, explicit effort and Fast payloads, operation overrides, account-switch races, discovery retries and legacy-runtime behavior. Tests use fake/local providers and must not consume ChatGPT quota.

Independent review also repaired recovery from a saved Fast setting on an older runtime, the visibility of an unsupported inherited global effort, and preservation of per-operation agent/model/effort settings during initial migration. Global Provider Default clears an explicit effort; a prompt's Inherit Global clears its override without changing the global choice. An old runtime keeps Normal selectable and reports incompatible explicit options instead of silently ignoring them.

Focused validation on 2026-10-02 passes 161 Flutter unit tests across AI Assist, settings, migration and runtime routing, 10 reading-diff regressions and 77 widget tests across model discovery, account controls, settings and text actions. Native filters pass 13 ChatGPT cases, 6 remote-forwarding cases, 19 existing AI Assist request cases and 3 settings-validation cases. Full Flutter analysis reports no issues in 15 seconds; formatting, generated EOF normalization, `cargo fmt --all -- --check`, Clippy for `alera-cli` and `alera-core --features runtime` with `--tests -- -D warnings`, the 500-line ratchet and whitespace checks pass. Cargo validation removes inherited `ALERA_*` runtime variables. The regenerated mapper is included with its settings source.

These checks use local/fake providers and do not consume ChatGPT quota. The earlier Windows build, full-platform suites and original OAuth tests do not validate this later feature addition. Real account model visibility, reasoning acceptance and Fast eligibility still require manual acceptance on a rebuilt runtime; no live OAuth, account-token model query or provider inference was performed for this follow-up.

### Official Contract

OpenAI specifies account-token discovery at `/v1/models`, server display visibility and current account-specific model choices. Responses requires `store:false`, `stream:true` and array input in the SIWC flow. See [SIWC models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference) and [preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations).

Responses configures thinking through `reasoning.effort`; accepted values depend on the model. Normal/standard processing uses `service_tier: "default"`, while Fast uses `service_tier: "fast"`. See [reasoning models](https://developers.openai.com/api/docs/guides/reasoning) and [Fast mode](https://developers.openai.com/api/docs/guides/fast-mode).

The SIWC UI guidance includes a Fast choice with a higher plan/credit usage notice. Access varies by plan, client, workspace policy and rollout; implementing the request parameter does not establish live availability for an account. See [SIWC UI/UX guidelines](https://developers.openai.com/siwc/ui-ux-guidelines) and [ChatGPT/Codex speed](https://learn.chatgpt.com/docs/agent-configuration/speed).
