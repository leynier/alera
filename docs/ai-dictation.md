# AI Dictation Adoption Plan

## Status

This document is the implementation plan for AI Dictation. It records the product boundary and architecture before implementation begins.

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
- The concrete desktop instruction composer is **New Workspace** -> **Initial Prompt**. Desktop terminals can accept reviewed text through the existing paste path without submitting it. Mobile has the matching workspace prompt plus a terminal compose bar.
- The active runtime may be remote. Microphone access, temporary audio, local model files, local inference, and remote transcription credentials therefore belong to the client device, not the runtime host.
- The repository roadmap already selected sherpa-onnx as the intended offline speech stack. The first implementation should use that engine instead of adding whisper.cpp directly, while preserving an engine-neutral provider boundary.

## Spec

### Objective

Let a user dictate an instruction for any configured agent profile, review or edit the transcript, and place it into the normal Alera prompt path without changing how the selected agent is launched or how its prompt is delivered.

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

#### Active Agent Terminal

1. The user opens AI Dictation from a terminal associated with a supported agent run.
2. Alera records and transcribes into a small transcript editor layered above the terminal.
3. The user edits the text and chooses **Insert Into Terminal**.
4. Alera calls the existing `TerminalSessionHandle.pasteText` path without adding Enter.
5. The user can continue editing in the agent TUI and submits through the normal terminal interaction.

AI Dictation must not write to ordinary shell terminals in the first release. The control is shown only when Alera has matched the terminal to a supported agent run.

### In Scope For The First Public Release

- Desktop macOS, Windows, and Linux.
- The New Workspace initial prompt and supported active agent terminals.
- Record, stop, cancel, retry, and edit behavior.
- One application-wide dictation session.
- Local-only, local-preferred, remote-preferred, and remote-only modes.
- sherpa-onnx with the multilingual Whisper base ONNX model as the default local provider.
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

- Every transcript remains editable before it reaches an existing prompt or terminal path.
- AI Dictation never appends Enter, invokes Create And Start Agent, or creates a dispatch.
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
LocalSherpaOnnxProvider   RemoteCompatibleProvider
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
       prompt editor or terminal paste
                    |
                    v
         existing Alera submission path
```

The runtime host receives only the final prompt through existing calls such as `agentProfile.launch`, or terminal bytes through the existing terminal transport. It never receives microphone audio, model files, provider credentials, or intermediate transcripts.

### Flutter Feature Layout

```text
lib/src/features/ai_dictation/
  application/
    ai_dictation_controller.dart
    ai_dictation_providers.dart
    ai_dictation_provider_manager.dart
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
    local_sherpa_onnx_provider.dart
    remote_compatible_provider.dart
    ai_dictation_model_catalog.dart
    ai_dictation_model_store.dart
  presentation/
    ai_dictation_overlay.dart
    ai_dictation_settings_pane.dart
```

Reusable visual controls belong in `lib/src/design_system/`, use the `Alera` prefix, remain presentational, and include co-located `*.preview.dart` previews. Feature widgets wire those controls to generated Riverpod providers.

### Rust Layout

```text
rust/src/api/ai_dictation.rs
rust/src/api/ai_dictation/
  credentials.rs
  local_transcription.rs
  model_files.rs
  remote_transcription.rs
```

This code belongs to the embedded `alera_native` library, not `alera-cli` or the runtime host. Work is dispatched to Tokio blocking tasks or dedicated native workers so model load and inference never run on the Flutter main isolate. Any new Rust API is exposed through flutter_rust_bridge and requires `make frb-generate` after the full API batch.

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

The generated `AiDictationController` is application-scoped and owns exactly one session:

```text
idle
  -> requestingPermission
  -> recording
  -> stopping
  -> downloadingModel, when required
  -> transcribing
  -> review
  -> inserting
  -> idle
```

Permission denial, no speech, provider failure, and model failure transition to an error state that keeps the original editor text unchanged. Cancellation from any non-idle state releases the microphone, cancels provider work, removes temporary files, and returns to idle.

### Audio Capture

Use the Flutter `record` package for the first implementation because it supports microphone recording and amplitude on all target desktop platforms. Capture mono PCM WAV and request 16 kHz when the platform supports it. The native backend validates the WAV header and resamples to the engine's required format when the operating system returns a different rate.

Linux packaging must explicitly probe the `record` package's PulseAudio and FFmpeg requirements in CI and on the supported distributions. If the packaged application cannot provide a dependency-complete capture path, the Linux release is gated until a native `cpal` capture implementation replaces the plugin. Do not silently ship a Linux button that always fails.

The existing macOS microphone usage description must be rewritten for AI Dictation, and both Debug and Release entitlements must include audio input. Windows and Linux permission or dependency failures return actionable next steps.

### Local Provider

Use sherpa-onnx through the embedded Rust library. sherpa-onnx supports offline ASR, VAD, the three desktop operating systems, Dart, and Rust. Its Whisper exports include multilingual base models, which keeps English, Spanish, and automatic language detection in the initial scope while matching the existing roadmap.

The initial catalog entry is `sherpa-onnx-whisper-base`, using the published int8 encoder when supported. The model is downloaded after explicit user action and is not bundled with every Alera installation.

Model files live under the client application's support directory:

```text
models/ai-dictation/sherpa-onnx-whisper-base/<catalog-version>/
```

The application bundles a model catalog containing the model id, source URL, SHA-256 values, compressed and installed sizes, required filenames, language coverage, and license metadata. Downloads go to a staging directory, verify every file, and move into place atomically. Cancellation or verification failure removes only the resolved staging directory. Model deletion uses the same exact model-root validation.

whisper.cpp remains a possible future provider. It is not added alongside sherpa-onnx in the first release because two local inference stacks would duplicate packaging, acceleration, model, and test work without improving the initial user flow.

### Remote Provider

The first remote adapter implements the common `POST /v1/audio/transcriptions` multipart shape. Settings include an HTTPS base URL, model name, language, and timeout. The default URL may target OpenAI, while a custom organization endpoint can implement the same contract.

The API key is stored in the operating system credential store through the embedded native layer. It is never persisted in `AleraSettings`, `runtime.sqlite`, Drift, diagnostics, or logs. If secure storage is unavailable, remote dictation remains unavailable instead of falling back to a plaintext credential file.

Remote requests originate from the client device because the recording is client-owned. The provider must enforce a maximum duration and upload size, redact authentication and sensitive query parameters from failures, and delete the temporary recording in a `finally` path.

### Provider Policy

- **Local Only** always uses the installed local model and never offers an upload action.
- **Local Preferred** is the default. It uses local transcription first and offers **Retry Remotely** only after an explicit local failure and only when a remote provider is configured.
- **Remote Preferred** uses the configured remote provider after first-use consent and offers an explicit local retry when a model is installed.
- **Remote Only** uses only the configured remote provider.

No mode changes providers because of confidence. Every off-device transition is either selected in settings before recording or chosen by the user after a visible failure.

### Device-Local Settings

Add `AiDictationSettings` to the locally persisted `AleraSettings` model. `RuntimeSettingsRepository` must preserve it through the legacy/local merge but omit it from `runtimeSettings.update`, keeping settings tied to the microphone and model device even when the selected runtime is remote.

Settings include enabled state, provider policy, language, local model id, remote base URL, remote model, timeout, first-use consent version, and text insertion preference. Credentials and model inventory are not serialized into this model.

Add a dedicated **AI Dictation** settings section with **General**, **Local Model**, **Remote Provider**, and **Privacy** groups. All visible labels use title case and explanatory copy uses sentence case.

### Text Insertion And Normalization

The first release performs only deterministic, loss-minimizing normalization:

- Convert CRLF to LF.
- Remove invalid control characters other than LF and tab.
- Trim leading and trailing whitespace.
- Collapse runs of spaces without changing line breaks.

Do not add punctuation, rewrite terminology, expand abbreviations, or interpret commands. Spoken punctuation and profile vocabulary replacement can be added later as explicit options with unit-tested rules.

For a Flutter text editor, replace the current selection and place the caret after the inserted transcript. An empty selection inserts at the caret. For a terminal, show a separate review editor first, then call `pasteText` without Enter.

### Agent Context

The selected profile name and agent type may be supplied as non-authoritative transcription hints. The first release derives those values from the existing profile and agent status records and does not modify `AgentProfile`, runtime schemas, or protocol versions.

A future additive profile field may store vocabulary hints after the corpus demonstrates that global terminology is insufficient. Prompt prefixes are excluded because they are agent instructions rather than speech recognition context and the existing `customPrompt` field already owns persistent profile instructions.

### Privacy, Security, And Diagnostics

- Raw audio remains on the client device in every mode until a visible remote request begins.
- The local provider performs no network access after model installation.
- The transcript is excluded from telemetry, crash breadcrumbs, and diagnostic bundles.
- Logs may include state, provider id, model id, input duration, elapsed time, byte count, and a redacted error code. They must not include transcript text, raw audio, credentials, or a custom endpoint's sensitive components.
- Temporary audio uses a session-specific directory and is deleted after success, cancellation, or terminal failure. Startup cleanup removes orphan session directories older than the maximum recording and transcription window.
- Remote consent names the provider, endpoint host, and the fact that audio leaves the device.
- Model downloads require HTTPS and catalogued checksums.
- The orchestration audit system continues to see only the final prompt through its existing behavior.

## Tasks

### Phase 0: Contracts And Test Harness

- Add `AiDictationSettings`, domain contracts, errors, state, cancellation, and generated Riverpod providers.
- Keep the settings model device-local through `RuntimeSettingsRepository` and add serialization tests.
- Add a fake provider, fake recorder, and an Alera-specific audio corpus manifest.
- Add selection-aware text insertion helpers and tests.
- Add presentational design-system controls with previews.
- Add the AI Dictation settings navigation and search entries.

Exit criterion: a fake transcript can move through every state and insert into a test editor without submitting anything.

### Phase 1: Capture And Surface Integration

- Add `record` and implement permission, start, stop, cancel, duration, amplitude, and temporary WAV lifecycle.
- Pace amplitude updates to at most 10 Hz.
- Integrate the reusable control with New Workspace.
- Add the supported-agent terminal overlay and insert through `TerminalSessionHandle.pasteText` without Enter.
- Add one global session guard and focus behavior.
- Add platform permission metadata and Linux dependency probes.

Exit criterion: real audio reaches a fake transcriber on all three desktop platforms and no flow submits a prompt.

### Phase 2: Remote Quality Baseline

- Add native secure credential storage without plaintext fallback.
- Add the OpenAI-compatible provider, timeout, cancellation, size limits, redacted errors, and connection test.
- Add first-use remote disclosure and persistent consent version.
- Add provider labels to recording and transcription states.
- Add mock-server integration tests for success, authentication failure, timeout, cancellation, malformed payload, and oversized recording.

Exit criterion: a user can dictate, review, and insert text through a configured remote endpoint while raw audio is removed and secrets are absent from logs.

### Phase 3: Offline Desktop Provider

- Pin sherpa-onnx and document its source and model licenses.
- Add the embedded native transcription API and regenerate FRB bindings once after the API batch.
- Package native libraries for the current desktop release architectures: macOS arm64, Windows x64, and Linux x64.
- Add the model catalog, resumable download, SHA-256 verification, atomic installation, removal, and disk-space preflight.
- Run model load and inference outside the Flutter main isolate with bounded concurrency of one.
- Implement language override, automatic detection, cancellation, and structured native errors.
- Add a benchmark runner that replays the checked-in corpus manifest against externally downloaded audio fixtures.

Exit criterion: local-only mode works without network access after model installation and passes the latency, memory, cancellation, and corpus release gates on the qualification matrix.

### Phase 4: Provider Policy And Hardening

- Implement all four provider policies and explicit retry actions.
- Preserve the recording across a recoverable provider failure, then delete it when the review flow ends.
- Add startup orphan cleanup and diagnostic metadata tests.
- Exercise model corruption, low disk, revoked permission, device removal, runtime switching, app close, and simultaneous-session cases.
- Add the keyboard action to the central keyboard registry if user testing supports a push-to-talk shortcut. Do not add an ad hoc key handler.
- Update user documentation and privacy copy.

Exit criterion: provider failures never lose typed text, never cause a silent upload, and never leave raw audio behind after the session closes.

### Phase 5: Mobile Adoption

- Reproduce the stable domain contract inside the separate `alera_mobile` package without introducing a dependency on the desktop package.
- Add device-local settings and secure credentials appropriate to Android and iOS.
- Integrate with Mobile New Workspace and `TerminalComposeBar`.
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

- New Workspace record -> transcribe -> insert -> edit -> existing create callback.
- Terminal record -> transcribe -> review -> paste, asserting that no carriage return is written.
- Permission denial, no speech, retry, and cancellation while preserving prior editor contents.
- Local and remote provider indicators and first-use consent.
- Settings model download, corruption recovery, removal, and secure-provider availability.
- At most one active dictation overlay across windows and surfaces.
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
| sherpa-onnx packaging increases release size or complicates native builds | Package the engine with Alera but download models separately; pin versions and test every release target in CI. |
| The `record` Linux backend depends on host tools | Add a fail-closed dependency probe and gate Linux release; replace capture with native `cpal` if supported distributions cannot meet the dependency contract. |
| Local inference consumes too much memory or blocks rendering | Use the base model, one native worker, lazy model loading, explicit unload, and frame-time benchmarks. |
| Remote configuration leaks repository information | Require visible consent, secure credentials, HTTPS, strict redaction, and no automatic upload. |
| Transcription changes negation or technical identifiers | Keep text cleanup minimal, build an Alera corpus, show editable review, and never auto-submit. |
| Device-local settings are accidentally copied to a remote runtime | Persist in local `AleraSettings` only and add a contract test for the runtime update payload. |
| Two UI surfaces compete for the microphone | Use one application-scoped controller and focus the active session. |

## Assumptions

- The first implementation is a sequence of focused PRs, not one feature branch containing every phase.
- Desktop remains the first release target; mobile begins only after the desktop contracts are stable.
- The existing agent status projection can identify supported agent terminals for the terminal control.
- The initial model catalog may point to upstream model artifacts only after license review and repository-owned checksum pinning.
- Remote endpoints implement the multipart transcription response shape with a top-level `text` value; vendor-specific streaming is deferred.
- The user keeps responsibility for reviewing and submitting every generated instruction.

## References

- [sherpa-onnx repository](https://github.com/k2-fsa/sherpa-onnx)
- [sherpa-onnx Whisper model documentation](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/whisper/export-onnx.html)
- [Flutter record package](https://pub.dev/packages/record)
- [OpenAI audio transcription endpoint](https://platform.openai.com/docs/api-reference/audio/createTranscription)
