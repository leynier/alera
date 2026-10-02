# ChatGPT AI Assist

## Spec

Add ChatGPT as an optional AI Assist provider using OpenAI's open-source Sign in with ChatGPT flow. Users connect, select and disconnect ChatGPT account registrations in desktop AI Assist settings. Credentials belong to the runtime, remain outside synced settings, and never reach paired phones. Existing providers and defaults stay unchanged. ChatGPT generates text from the context Alera supplies, with no local tool execution.

## Design

The runtime owns loopback OAuth with PKCE and OIDC validation, protected credential storage, serialized refresh, account-specific model discovery and cancellable Responses streaming. A new additive capability gates desktop support. The desktop and paired-phone AI Assist paths share inference on the runtime that owns the request. Remote runtimes need their own connection. Account administration is local-client-only.

Credentials are encrypted with ChaCha20-Poly1305 in an atomically replaced runtime file. The system credential store holds only its random encryption key, since a multi-account token record exceeds [Windows Credential Manager's 2560-byte limit](https://learn.microsoft.com/en-us/windows/win32/api/wincred/ns-wincred-credentiala). Linux can fall back to an owner-only file when Secret Service is unavailable. Credential I/O runs outside the server actor. Account changes cancel requests using the previous account; logout retains registration and host identity for reauthorization.

## Tasks

- Completed: implement OAuth, protected registrations, refresh and disconnect.
- Completed: connect Responses inference and model discovery to AI Assist.
- Completed: add desktop account controls and provider selection.
- Completed: regenerate Dart code, normalize generated files, and validate the focused Rust and Flutter suites.
- Completed: Claude Opus Dev reviewed and refined the UI through Alera orchestration (task `task_e42fee33c2a246d1`), including account rows, pending and error states, accessibility and first-use notice.
- Pending manual acceptance: real ChatGPT consent, account eligibility and an AI Assist inference request on a rebuilt runtime.

## Tests

Validate callback state/client binding, signed ID-token issuer/audience/nonce, account isolation, credential permissions, refresh rotation and terminal errors. Verify request shape, catalog visibility/order, cancellation, incomplete/error streams and completion-only success. Check provider serialization, runtime routing and account controls without external inference.

Verified locally: 147 Flutter unit/widget tests, 14 ChatGPT runtime tests, 69 existing AI Assist runtime tests, 3 mobile allowlist tests and 3 shared runtime settings tests. Flutter analysis, Rust Clippy with warnings denied, the 500-line ratchet and whitespace checks pass. Tests include discarding a stale model catalog after changing accounts. No live OAuth or inference call was performed.

## Scope And Sources

The preview supports text chat through Responses with client-managed history. Audio/video input and transcription are explicitly unsupported; this change does not enable dictation or conversational voice. AI Assist may still clean up text that another dictation provider has already transcribed.

- [Registration and sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [Accounts and sessions](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions)
- [Models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
- [Preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)

Real OAuth consent and account eligibility require a browser and a ChatGPT account; mocked local tests do not establish live acceptance.
