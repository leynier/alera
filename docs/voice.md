# Voice Home Agent

Alera’s global voice agent lives outside product workspaces. Speech is a
replaceable I/O pipeline. Reasoning stays in a persistent CLI agent that uses
the existing orchestration CLI and subscriptions.

## Home folder

The runtime owns `{runtimeDir}/home` as a folder project (`alera-home`) with one
shared task (`alera-home`, named Voice). That task is hidden from the sidebar
and from ordinary `project.list` / `workspace.list` responses. The host writes
and may overwrite `AGENTS.md` (plus one-line `CLAUDE.md` / `GEMINI.md`
pointers) whenever the contract version changes. Do not add a
`WorkspaceKind::Runtime`; home is a normal folder project with a Main task.

The home agent speaks with `alera voice speak --text "..."` and delegates with
`alera orchestration delegate --workspace <id>`.

## Pipeline

Settings → Voice chooses:

- **Chained:** independent STT and TTS providers. Default STT is local Whisper;
  default TTS is Gemini Flash TTS.
- **Realtime:** one speech-to-speech WebSocket (Gemini Live or GPT Realtime).
  The host owns the socket. The model must not call tools or answer content;
  it transcribes the mic and speaks host-supplied `alera voice speak` text.
  User turns still go to the home CLI. Default chained path stays Whisper +
  Gemini Flash TTS.

Barge-in always stops local playback immediately. A busy home PTY queues the
new turn unless the user says an explicit cancel (`para`, `stop`, `cancel`,
`basta`) — that sends Ctrl+C to the home agent before the new prompt.

Desktop and mobile realtime playback stream PCM16 through SoLoud as chunks
arrive (`voice.audio` / `voice.audioDone`). Chained TTS still plays a WAV
file (desktop via `ProcessRunner`, mobile via `just_audio`). `Ack while
thinking` speaks a short confirmation when a turn is injected. Gemini
transcribe uses the Gemini API key, not the OpenAI-compatible dictation
engine. A dropped realtime socket reconnects while the session is still
listening.

Capability: `voiceHomeAgentV1` (additive, protocol v4 unchanged).

Host verbs: `voice.ensure`, `voice.status`, `voice.start`, `voice.stop`,
`voice.speak`, `voice.turn`, `voice.synthesize`, `voice.spoken`,
`voice.audio`, `voice.activity`, and `voice.credentials.*`. Realtime playback
arrives as `voice.audio` / `voice.audioDone`. Mobile uses the `mobile.voice.*`
aliases, including `mobile.voice.credentials.*`. Pipeline, STT/TTS, realtime
model, home profile, and API keys are runtime settings; the phone edits the
same host store as desktop. Keys stay in the runtime keyring.

Dictation stays a separate push-to-talk product. Voice reuses Whisper models
and OpenAI-compatible dictation engines, not the dictation UX.
