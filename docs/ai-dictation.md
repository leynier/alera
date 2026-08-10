# AI Dictation Adoption Plan

## Status

This document is the implementation plan for AI Dictation. It records the product boundary and architecture before implementation begins. It was reconciled with Alera `main` at `c3332606` after the terminal composer, native Codex chat, unified text actions, and current settings architecture landed.

AI Dictation converts microphone audio into editable instructions for Alera agents. It does not execute an instruction, create an orchestration task, or submit terminal input by itself.

## Conversation Analysis

The shared design conversation established several principles that fit Alera and should be retained:

- Separate audio capture, transcription, text cleanup, prompt editing, and agent delivery.
- Hide local and remote speech engines behind one provider contract.
- Keep the transcript editable and require the user's existing send or create action.
- Make off-device processing visible and never silently upload a recording.
- Delete raw audio by default and keep transcript contents out of telemetry.
- Keep local model management independent from prompt delivery.

The conversation also assumed product surfaces and ownership boundaries that do not match the current repository:

- Alera does not currently have Flutter task, dispatch, or coordinator specification composers. Orchestration tasks and dispatches are runtime and agent workflows, so the first release must not invent a second orchestration UI.
- Desktop now has three concrete editable prompt surfaces: **New Workspace** -> **Initial Prompt**, `TerminalComposer` backed by the reusable `AleraComposer`, and the native Codex chat composer. AI Dictation should integrate with those editors instead of adding a terminal overlay or a parallel prompt UI.
- `TerminalComposer` is available to ordinary shell and agent terminals and submits only when the user activates its existing send action. Dictation can therefore be offered to every terminal composer without depending on agent-status matching.
- Mobile now has matching New Workspace and terminal composers plus native Codex chat, but it remains a later phase because it is a separate package with different capture, permission, storage, and thermal constraints.
- The active runtime may be remote. Microphone access, temporary audio, local model files, local inference, and remote transcription credentials therefore belong to the client device, not the runtime host.
- The repository roadmap previously named sherpa-onnx, but the product decision is to use Whisper through whisper.cpp as the initial offline engine. The provider boundary remains engine-neutral so this choice does not leak into prompt or orchestration code.

## Spec

### Objective

Let a user dictate an instruction, review or edit the transcript in the current Alera composer, and submit it through that composer's existing action without changing agent launch, terminal submission, or Codex chat delivery.

The invariant is:

> AI Dictation produces candidate text. Existing Alera behavior decides whether and how that text is sent.

### Audience

The first release targets desktop users on macOS, Windows, and Linux who create workspaces from prompts or interact with a supported agent in a terminal. Mobile support follows after the desktop provider and privacy contracts are stable.

### User Flows

#### New Workspace

1. The user selects an agent profile in **New Workspace**.
2. The user activates **AI Dictation** beside **Initial Prompt**.
3. Alera requests microphone permission when needed and records locally.
4. The user stops or cancels recording.
5. The configured provider transcribes the recording.
6. Alera inserts the transcript at the current text selection.
7. The user edits the prompt and chooses **Create And Start Agent** through the existing flow.

The selected profile supplies context such as its name and agent type to the transcription request. It does not change the speech model or automatically add a prompt prefix in the first release.

#### Terminal Composer

1. The user shows the existing terminal composer and activates **AI Dictation**.
2. Alera records and transcribes on the client device.
3. Alera inserts the transcript into `TerminalComposerController.textController` at the current selection.
4. The user edits the text and activates the composer's existing **Send Prompt** action.
5. `TerminalComposer` builds the normal submission and calls `TerminalSessionHandle.submitText`; dictation never calls that method itself.

#### Native Codex Chat

1. The user activates **AI Dictation** from the native Codex chat composer.
2. Alera records and transcribes without involving the runtime host or Codex app server.
3. Alera inserts the transcript into the existing `_composer` controller without changing attachments, draft items, model, reasoning, permission, plan, or collaboration settings.
4. The user edits the message and activates the existing send action.
5. Dictation never calls `CodexChatController.send` or `steer` itself.

### In Scope For The First Public Release

- Desktop macOS, Windows, and Linux.
- The New Workspace initial prompt, every desktop terminal composer, and native Codex chat composer.
- Record, stop, cancel, retry, and edit behavior.
- One application-wide dictation session.
- Local-only, local-preferred, remote-preferred, and remote-only modes.
- whisper.cpp with the multilingual Whisper base `ggml` model as the default local provider.
- An OpenAI-compatible multipart transcription provider with configurable HTTPS base URL and model.
- Automatic language detection plus an explicit language override.
- Visible local or remote provider status before recording begins and while transcribing.
- Device-local settings, OS credential storage, model download, checksum verification, and removal.
- Temporary WAV cleanup after success, cancellation, and failure.
- Optional provider metadata such as detected language, duration, and confidence when the provider exposes it.

### Non-Goals For The First Public Release

- Automatic prompt submission or agent execution.
- Natural-language intent parsing or JSON command generation.
- LLM rewriting, summarization, or instruction improvement.
- Automatic provider switching based on an uncalibrated confidence score.
- Silent remote fallback.
- Streaming partial transcripts, always-listening mode, wake words, or speaker identification.
- Custom dictation fields on agent profile records.
- Raw audio or transcript persistence, history, synchronization, or orchestration audit events.
- A new runtime protocol verb for audio.
- Mobile implementation.

### Success Criteria

- Every transcript remains editable in its initiating composer before the user submits it.
- AI Dictation never appends Enter, invokes Create And Start Agent, calls a terminal or Codex send/steer method, or creates a dispatch.
- Local-only mode performs no network request after its model is installed.
- A local-preferred failure preserves the recording long enough to offer an explicit remote retry, then deletes it when the flow ends.
- A recording is never uploaded until the user has enabled a remote mode and accepted the first-use disclosure for that provider.
- Cancellation works during permission, recording, model load, model download, local inference, and remote upload.
- Starting a second session focuses the existing session instead of opening another microphone stream.
- Raw audio is absent after the session finishes unless a diagnostics retention option was explicitly enabled in a future release.
- Model loading and transcription do not block the Flutter main isolate.
- Recording feedback is paced to at most 10 UI updates per second so continuous audio does not request a Flutter frame for every audio chunk.
- A 10-second reference clip transcribes locally within 5 seconds on the documented baseline macOS, Windows, and Linux qualification devices.
- The Alera speech corpus preserves every critical negation in its release-gate samples and recognizes at least 95 percent of the catalogued agent and repository terms.
- Closing or replacing the initiating composer during transcription never inserts text into another surface; Alera retains the result in a review fallback with **Copy** and **Discard** actions.

## Design

### Ownership And Data Flow

```text
Microphone on client device
        |
        v
AudioCaptureService
        |
        v
temporary mono PCM WAV
        |
        v
AiDictationProviderManager
        |
        +-----------------------+
        |                       |
        v                       v
LocalWhisperCppProvider   RemoteCompatibleProvider
embedded client Rust      HTTPS from client device
        |                       |
        +-----------+-----------+
                    |
                    v
             AiDictationResult
                    |
                    v
          deterministic normalization
                    |
                    v
       registered composer target
                    |
                    v
         existing Alera submission path
```

The runtime host receives only text submitted later through existing workspace launch, terminal, or Codex chat calls. It never receives microphone audio, model files, provider credentials, or intermediate transcripts.

### Flutter Feature Layout

```text
lib/src/features/ai_dictation/
  application/
    ai_dictation_controller.dart
    ai_dictation_providers.dart
    ai_dictation_provider_manager.dart
    ai_dictation_target_registry.dart
    ai_dictation_text_insertion.dart
  domain/
    ai_dictation_capabilities.dart
    ai_dictation_error.dart
    ai_dictation_provider.dart
    ai_dictation_request.dart
    ai_dictation_result.dart
    ai_dictation_settings.dart
    ai_dictation_state.dart
  infra/
    native_ai_dictation_backend.dart
    record_audio_capture_service.dart
    local_whisper_cpp_provider.dart
    remote_compatible_provider.dart
    ai_dictation_model_catalog.dart
    ai_dictation_model_store.dart
  presentation/
    ai_dictation_control.dart
    ai_dictation_review_dialog.dart
    ai_dictation_settings_pane.dart
```

Reusable visual controls belong in `lib/src/design_system/`, use the `Alera` prefix, remain presentational, and include co-located `*.preview.dart` previews. Add an optional presentational action slot to `AleraComposer` instead of importing dictation into the design system. `TerminalComposer`, the New Workspace form, and the private native Codex composer each supply the feature-level dictation control and register their own text target.

### Rust Layout

```text
rust/src/api/ai_dictation.rs
rust/src/api/ai_dictation/
  credentials.rs
  local_transcription.rs
  model_files.rs
  remote_transcription.rs
```

This code belongs to the root `alera_native` package built by Cargokit, not `alera-cli`, `alera-core`, or the runtime host. whisper.cpp is compiled and statically linked through the pinned `whisper-rs` dependency, so the app does not ship a second executable or dynamically located speech library. Blocking model load, inference, hashing, and filesystem work runs on a bounded native worker; network work uses the existing Tokio runtime. Any new Rust API is exposed through flutter_rust_bridge and requires `make frb-generate` after the full API batch.

### Provider Contract

The Dart domain owns the stable contract. Native bridge types are translated in the infrastructure implementation.

```dart
abstract interface class AiDictationProvider {
  String get id;

  Future<AiDictationCapabilities> capabilities();

  Future<AiDictationResult> transcribe(
    AiDictationRequest request,
    AiDictationCancellation cancellation,
  );
}
```

`AiDictationRequest` contains the audio path, language override, selected profile name, agent type, and vocabulary hints. `AiDictationResult` contains text, provider id, local or remote ownership, elapsed time, model id, optional detected language, and optional confidence.

Confidence is metadata only. Providers do not expose agent commands, dispatch records, or orchestration mutations.

### State Model

The generated `AiDictationController` is application-scoped and owns exactly one session. An `AiDictationTargetRegistry` holds short-lived opaque target ids for mounted composers and their insertion callbacks; the controller stores only the initiating target id, never a Flutter controller or `BuildContext`.

```text
idle
  -> preparing
  -> requestingPermission
  -> recording
  -> stopping
  -> transcribing
  -> inserting -> idle, when the target is still registered
  -> reviewFallback -> idle, when the target disappeared
```

The preparing state verifies the configured provider, installed model, disk space, and target before requesting microphone access. A local model is installed explicitly in Settings before recording, so Alera never retains a recording while downloading a model. Permission denial, no speech, provider failure, and model failure transition to an error state that keeps the original editor text unchanged. Cancellation from any non-idle state releases the microphone, cancels provider work, removes temporary files, and returns to idle. If the target unregisters before insertion, the transcript opens in the review fallback and is never redirected to whichever editor is currently focused.

### Audio Capture

Use the Flutter `record` package for the first implementation because it provides file recording, permission checks, and amplitude on all target desktop platforms. Resolve session-specific temporary paths through the already-installed `path_provider` package, capture mono PCM WAV, and request 16 kHz when the platform supports it. The native backend validates the WAV header and resamples to the engine's required format when the operating system returns a different rate.

Linux packaging must explicitly probe the `record` package's PulseAudio and FFmpeg requirements in CI and on the supported distributions. If the packaged application cannot provide a dependency-complete capture path, the Linux release is gated until a native `cpal` capture implementation replaces the plugin. Do not silently ship a Linux button that always fails.

The existing macOS microphone usage description must be rewritten for AI Dictation, and both Debug and Release entitlements must include audio input. Windows and Linux permission or dependency failures return actionable next steps.

### Local Provider

Use whisper.cpp through the embedded Rust library. Add a pinned `whisper-rs` dependency only to the root `alera_native` package and call its library API directly. Do not add it to `alera-cli`, do not spawn `whisper-cli`, and do not route inference through the terminal host. Before implementation proceeds past the native spike, prove that the pinned binding exposes cooperative abort during inference; if it does not, add the smallest reviewed C API wrapper around whisper.cpp's abort callback instead of accepting uncancellable work.

The initial catalog entry is `whisper-cpp-base`, using the published multilingual `ggml-base.bin` model. Do not use `base.en`, because English and Spanish are both in the first-release scope. The model is downloaded after explicit user action and is not bundled with every Alera installation. Quantized and larger models can be added as separate catalog entries after the base model establishes the quality and performance baseline.

Model files live under the client application's support directory:

```text
models/ai-dictation/whisper-cpp-base/<catalog-version>/
```

The application bundles a model catalog containing the model id, source URL, SHA-256 values, download and installed sizes, required filenames, language coverage, and license metadata. The Rust backend owns streamed download, SHA-256 verification, disk-space preflight, staging, atomic installation, and exact-root removal so large-file hashing and filesystem work stay off the Flutter main isolate. Cancellation or verification failure removes only the resolved staging directory.

sherpa-onnx remains a possible future provider. It is not added alongside whisper.cpp in the first release because two local inference stacks would duplicate packaging, acceleration, model, and test work without improving the initial user flow.

### Remote Provider

The first remote adapter implements the common `POST /v1/audio/transcriptions` multipart shape. Settings include an HTTPS base URL, model name, language, and timeout. The default URL may target OpenAI, while a custom organization endpoint can implement the same contract.

The API key is stored in the operating system credential store through the embedded native layer. It is never persisted in `AleraSettings`, `runtime.sqlite`, Drift, diagnostics, or logs. If secure storage is unavailable, remote dictation remains unavailable instead of falling back to a plaintext credential file.

Remote requests originate from the client device because the recording is client-owned. The provider must enforce a maximum duration and upload size, redact authentication and sensitive query parameters from failures, and delete the temporary recording in a `finally` path.

### Provider Policy

- **Local Only** always uses the installed local model and never offers an upload action.
- **Local Preferred** is the default. It uses local transcription first and offers **Retry Remotely** only after an explicit local failure and only when a remote provider is configured.
- **Remote Preferred** uses the configured remote provider after first-use consent and offers an explicit local retry when a model is installed.
- **Remote Only** uses only the configured remote provider.

Local modes with no installed model fail during preparation with **Open AI Dictation Settings** and do not start recording. Remote modes with no usable credential or endpoint behave the same way. No mode changes providers because of confidence. Every off-device transition is either selected in settings before recording or chosen by the user after a visible failure.

### Device-Local Settings

Add `AiDictationSettings` beside `AiTextGenerationSettings` in the locally persisted `AleraSettings` model, with generated `dart_mappable` output and `SettingsController` update/reset methods. `RuntimeSettingsRepository` must preserve the legacy/local value during every runtime merge and omit it from `runtimeSettings.update`, keeping settings tied to the microphone and model device even when the selected runtime is remote.

Settings include enabled state, provider policy, language, local model id, remote base URL, remote model, timeout, first-use consent version, and text insertion preference. Credentials and model inventory are not serialized into this model.

Add a dedicated **AI Dictation** settings section with **General**, **Local Model**, **Remote Provider**, and **Privacy** groups. All visible labels use title case and explanatory copy uses sentence case.

### Text Insertion And Normalization

The first release performs only deterministic, loss-minimizing normalization:

- Convert CRLF to LF.
- Remove invalid control characters other than LF and tab.
- Trim leading and trailing whitespace.
- Collapse runs of spaces without changing line breaks.

Do not add punctuation, rewrite terminology, expand abbreviations, or interpret commands. Spoken punctuation and profile vocabulary replacement can be added later as explicit options with unit-tested rules.

Every supported surface registers a `TextEditingController` insertion callback under an opaque target id. Replace the current valid selection and place the caret after the inserted transcript; an empty or invalid selection inserts at the end. Capture the target id when recording starts. If the editor value is unchanged, honor the selection captured at start; if the user edited while transcription ran, insert at the controller's current selection so stale offsets cannot overwrite newer text. Insertion never activates a workspace, terminal, or Codex send callback.

### Agent Context

Composer context may be supplied as non-authoritative transcription hints: New Workspace contributes the selected profile name and agent type, a terminal contributes matched agent status when available, and native Codex chat contributes only its known Codex target type. The first release does not modify `AgentProfile`, workspace tab records, runtime schemas, or protocol versions.

A future additive profile field may store vocabulary hints after the corpus demonstrates that global terminology is insufficient. Prompt prefixes are excluded because they are agent instructions rather than speech recognition context and the existing `customPrompt` field already owns persistent profile instructions.

### Privacy, Security, And Diagnostics

- Raw audio remains on the client device in every mode until a visible remote request begins.
- The local provider performs no network access after model installation.
- The transcript is excluded from telemetry, crash breadcrumbs, and diagnostic bundles.
- Logs may include state, provider id, model id, input duration, elapsed time, byte count, and a redacted error code. They must not include transcript text, raw audio, credentials, or a custom endpoint's sensitive components.
- Temporary audio uses a session-specific directory and is deleted after success, cancellation, or unrecoverable failure. Startup cleanup removes orphan session directories older than the maximum recording and transcription window.
- Remote consent names the provider, endpoint host, and the fact that audio leaves the device.
- Model downloads require HTTPS and catalogued checksums.
- The orchestration audit system continues to see only the final prompt through its existing behavior.

## Tasks

### Phase 0: Native Feasibility, Contracts, And Test Harness

- Prove a pinned `whisper-rs` and whisper.cpp revision builds inside the root `alera_native` package on the native release targets: macOS arm64, Windows x64, and Linux x64. Verify `alera-cli` and remote runtime artifacts do not acquire the dependency.
- Prove cooperative inference cancellation, deterministic model unload, and bounded one-job concurrency before committing to the binding. Record measured model-load time and retained RSS on each qualification platform.
- Add `AiDictationSettings`, domain contracts, errors, state, cancellation, and generated Riverpod providers.
- Keep the settings model device-local through `RuntimeSettingsRepository` and add serialization and runtime-payload tests.
- Add a fake provider, fake recorder, target registry, selection-aware insertion helper, and Alera-specific audio corpus manifest.
- Add presentational design-system controls with previews plus the **AI Dictation** settings section, groups, and search entries.

Exit criterion: all three release builds link the cancellable engine, and a fake transcript can move through every state into a registered test editor without invoking any submission callback.

### Phase 1: Capture And Surface Integration

- Add `record` and implement permission, start, stop, cancel, duration, amplitude, and temporary WAV lifecycle.
- Pace amplitude updates to at most 10 Hz.
- Add an optional presentational action slot to `AleraComposer`; integrate the feature control and target registration with New Workspace, `TerminalComposer`, and the native `_CodexComposer`.
- Insert only through each surface's existing `TextEditingController`; do not call workspace creation, `TerminalSessionHandle.submitText`, `CodexChatController.send`, or `steer`.
- Add one global session guard, initiating-target retention, and the **Copy** or **Discard** review fallback for a target that unmounts.
- Add platform permission metadata and Linux dependency probes.

Exit criterion: real audio reaches a fake transcriber on all three desktop platforms and no flow submits a prompt.

### Phase 2: Offline Whisper Provider

- Pin `whisper-rs`, its whisper.cpp source revision, and the Whisper model license metadata.
- Add the embedded native transcription API and regenerate FRB bindings once after the API batch.
- Keep whisper.cpp statically linked by Cargokit and add release-build coverage instead of packaging a separate library or executable.
- Add the model catalog and native streamed download, SHA-256 verification, atomic installation, removal, and disk-space preflight for multilingual `ggml-base.bin`.
- Run model load and inference outside the Flutter main isolate with bounded concurrency of one.
- Implement language override, automatic detection, cancellation, and structured native errors.
- Add a benchmark runner that replays the checked-in corpus manifest against externally downloaded audio fixtures.

Exit criterion: local-only mode works without network access after model installation and passes the latency, memory, cancellation, and corpus release gates on the qualification matrix.

### Phase 3: Optional Remote Provider

- Add native secure credential storage without plaintext fallback.
- Add the OpenAI-compatible provider, timeout, cancellation, size limits, redacted errors, and connection test.
- Add first-use remote disclosure and persistent consent version.
- Add provider labels to recording and transcription states.
- Add mock-server integration tests for success, authentication failure, timeout, cancellation, malformed payload, and oversized recording.

Exit criterion: a user who explicitly configures remote transcription can dictate and insert text while raw audio is removed and secrets are absent from settings, runtime payloads, diagnostics, and logs.

### Phase 4: Provider Policy And Hardening

- Implement all four provider policies and explicit retry actions.
- Preserve the recording across a recoverable provider failure, then delete it when the review flow ends.
- Add startup orphan cleanup and diagnostic metadata tests.
- Exercise model corruption, low disk, revoked permission, device removal, runtime switching, app close, and simultaneous-session cases.
- Add `toggleAiDictation` to the central keyboard registry and dispatcher with no default binding in the first release. It is available to the command palette and user keybinding editor, is allowed under terminal-first policy, and operates only when the target registry has a focused dictation-capable editor. Do not add an ad hoc key handler.
- Update user documentation and privacy copy.

Exit criterion: provider failures never lose typed text, never cause a silent upload, and never leave raw audio behind after the session closes.

### Phase 5: Mobile Adoption

- Reproduce the stable domain contract inside the separate `alera_mobile` package without introducing a dependency on the desktop package.
- Add device-local settings and secure credentials appropriate to Android and iOS.
- Integrate with Mobile New Workspace, `TerminalComposeBar`, and the native mobile Codex chat composer.
- Keep audio and inference on the phone even when connected to a remote runtime.
- Qualify smaller model choices, battery, thermal behavior, interruptions, Bluetooth routes, storage pressure, and platform permissions.

Exit criterion: mobile produces editable text in the existing composers and sends only the final user-approved text through the current mobile protocol.

## Tests

### Dart Unit Tests

- Every valid state transition and rejection of invalid concurrent starts.
- Cancellation from every non-idle state.
- Provider policy decisions with online, offline, configured, missing-model, and failure cases.
- No automatic remote fallback.
- Selection insertion, cursor placement, multiline insertion, and unchanged text on empty results.
- Original-selection insertion when the editor is unchanged, current-selection insertion after concurrent editing, and review fallback after target disposal.
- Deterministic normalization, including control characters and critical negations.
- Settings round-trip and proof that `runtimeSettings.update` omits AI Dictation.
- Temporary-path validation and cleanup scheduling.

### Rust Unit Tests

- WAV validation and resampling boundaries.
- Model catalog parsing, checksum mismatch, atomic install, cancellation, and exact-root deletion safety.
- Local inference cancellation and concurrency limit.
- Remote multipart construction, maximum sizes, timeout mapping, and secret redaction.
- Credential create, read, replace, and delete behavior without exposing values in errors.

### Widget And Integration Tests

- New Workspace record -> transcribe -> insert -> edit, asserting that the existing create callback is not invoked.
- Terminal composer record -> transcribe -> insert -> edit, asserting that `TerminalSessionHandle.submitText` is not invoked.
- Native Codex chat record -> transcribe -> insert -> edit, asserting that neither send nor steer is invoked and that attachments and draft items are unchanged.
- Permission denial, no speech, retry, and cancellation while preserving prior editor contents.
- Local and remote provider indicators and first-use consent.
- Settings model download, corruption recovery, removal, and secure-provider availability.
- At most one active dictation session across windows and surfaces.
- No continuous rebuild or frame request at the audio callback rate.

### Platform Qualification

- macOS Apple Silicon microphone permission, audio input entitlement, model load, and cancellation.
- Windows x64 permission, Media Foundation capture behavior, model load, and cancellation.
- Linux x64 dependency probe, microphone capture under supported desktop audio stacks, model load, and cancellation.
- Remote runtime selected while local dictation remains on the client.
- Offline operation after installing the model and restarting Alera without network access.

## Risks And Mitigations

| Risk | Mitigation |
| --- | --- |
| whisper.cpp increases build complexity or leaks into the runtime sidecar | Add it only to the root `alera_native` package, statically link it through Cargokit, download models separately, and prove all native release builds plus a dependency-tree assertion in Phase 0. |
| The `record` Linux backend depends on host tools | Add a fail-closed dependency probe and gate Linux release; replace capture with native `cpal` if supported distributions cannot meet the dependency contract. |
| Local inference consumes too much memory or blocks rendering | Use the base model, one native worker, lazy model loading, explicit unload, and frame-time benchmarks. |
| Remote configuration leaks repository information | Require visible consent, secure credentials, HTTPS, strict redaction, and no automatic upload. |
| Transcription changes negation or technical identifiers | Keep text cleanup minimal, build an Alera corpus, show editable review, and never auto-submit. |
| Device-local settings are accidentally copied to a remote runtime | Persist in local `AleraSettings` only and add a contract test for the runtime update payload. |
| Two UI surfaces compete for the microphone | Use one application-scoped controller and focus the active session. |
| The terminal and Codex composers evolve independently | Share target registration, insertion, and dictation controls while leaving each composer's existing submission semantics untouched. |

## Assumptions

- The first implementation is a sequence of focused PRs, not one feature branch containing every phase.
- Desktop remains the first release target; mobile begins only after the desktop contracts are stable.
- The first desktop release supports the current New Workspace, terminal composer, and native Codex chat surfaces; other text fields and structured Codex approval or question inputs are excluded.
- The initial model catalog may point to upstream model artifacts only after license review and repository-owned checksum pinning.
- Remote endpoints implement the multipart transcription response shape with a top-level `text` value; vendor-specific streaming is deferred.
- The user keeps responsibility for reviewing and submitting every generated instruction.

## References

- [whisper.cpp repository](https://github.com/ggml-org/whisper.cpp)
- [whisper.cpp model documentation](https://github.com/ggml-org/whisper.cpp/blob/master/models/README.md)
- [whisper-rs crate documentation](https://docs.rs/crate/whisper-rs/latest)
- [Flutter record package](https://pub.dev/packages/record)
- [OpenAI audio transcription endpoint](https://platform.openai.com/docs/api-reference/audio/createTranscription)
