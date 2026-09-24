import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:alera/src/features/ai_dictation/application/ai_dictation_providers.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_request.dart';
import 'package:alera/src/features/ai_dictation/infra/native_ai_dictation_provider.dart';
import 'package:alera/src/features/ai_dictation/infra/runtime_ai_dictation_provider.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/voice/domain/voice_activity_detector.dart';
import 'package:alera/src/features/voice/domain/voice_session_status.dart';
import 'package:alera/src/features/voice/domain/voice_settings.dart';
import 'package:alera/src/features/voice/infra/runtime_voice_client.dart';
import 'package:alera/src/features/voice/infra/voice_audio_io.dart';
import 'package:alera/src/features/voice/infra/voice_private_wav.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/process/process_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'voice_session_capture.dart';
part 'voice_session_controller.g.dart';
part 'voice_session_fields.dart';
part 'voice_session_playback.dart';

@Riverpod(keepAlive: true)
RuntimeVoiceClient runtimeVoiceClient(Ref ref) {
  final client = ref.watch(runtimeHostClientProvider);
  return RuntimeVoiceClient(client: client, capabilities: client);
}

@riverpod
Future<bool> voiceHomeAgentSupported(Ref ref) {
  return ref.watch(runtimeVoiceClientProvider).isSupported();
}

@Riverpod(keepAlive: true)
class VoiceSessionController extends _$VoiceSessionController
    with _VoiceSessionFields, _VoiceSessionPlayback, _VoiceSessionCapture {
  @override
  VoiceSessionStatus build() {
    unawaited(_events?.cancel());
    final client = ref.watch(runtimeVoiceClientProvider);
    _events = ref
        .watch(runtimeHostClientProvider)
        .runtimeEvents
        .listen(
          _onEvent,
          onDone: () {
            unawaited(_onTransportLost());
          },
        );
    ref.onDispose(() {
      unawaited(_events?.cancel());
      unawaited(_disposeSession(client));
    });
    return VoiceSessionStatus.empty;
  }

  @override
  Future<void> refresh() async {
    if (!await _client.isSupported()) {
      state = VoiceSessionStatus.empty;
      return;
    }
    state = await _client.status();
  }

  Future<void> start() async {
    if (_listening || _starting) {
      return;
    }
    _starting = true;
    final intent = _beginLocalShutdown();
    var epoch = _captureEpoch;
    try {
      await _awaitSettledShutdown();
      if (intent != _stopToken || _listening) {
        return;
      }
      _captureEpoch += 1;
      epoch = _captureEpoch;
      if (!await _client.isSupported()) {
        state = state.copyWith(
          lastError: 'Update this runtime to use the voice home agent.',
        );
        return;
      }
      if (epoch != _captureEpoch) {
        return;
      }
      state = await _client.start();
      if (epoch != _captureEpoch) {
        return;
      }
      _playbackEnabled = true;
      _playbackGeneration += 1;
      await _ensureAudio();
      _vad.reset();
      _vadPreroll.clear();
      _utterance.clear();
      _pendingRealtime.clear();
      _realtimeFlushing = false;
      _realtimePlayback.clear();
      _streamingPlayback = false;
      _playbackSends = Future<void>.value();
      _speakChain = Future<void>.value();
      _turnChain = Future<void>.value();
      _activePlaybackId = null;
      _rejectUnidentifiedPlayback = false;
      _invalidPlaybackIds.clear();
      _admittedPlaybackIds.clear();
      _realtime =
          state.realtime || _settings.pipeline == VoicePipeline.realtime;
      await _audio!.startCapture();
      if (epoch != _captureEpoch) {
        return;
      }
      _listening = true;
    } on Object catch (error) {
      if (epoch != _captureEpoch) {
        return;
      }
      await _rollbackStart(error);
    } finally {
      if (epoch == _captureEpoch) {
        _starting = false;
      }
    }
  }

  Future<void> _rollbackStart(Object error) async {
    final token = _beginLocalShutdown();
    VoiceSessionStatus? status;
    final shutdown = _sessionShutdown.then((_) async {
      try {
        await _stopLocalCapture();
      } on Object {
        // Native capture/playback cleanup must not skip host stop.
      }
      try {
        status = await _client.stop();
      } on Object {
        // Best-effort host rollback after a failed microphone start.
      }
    });
    _sessionShutdown = shutdown.catchError((Object _) {});
    await _sessionShutdown;
    if (token != _stopToken) {
      return;
    }
    state = (status ?? state).copyWith(
      lastError: error.toString(),
      phase: VoiceSessionPhase.idle,
    );
  }

  Future<void> stop() async {
    final token = _beginLocalShutdown();
    VoiceSessionStatus? status;
    final shutdown = _sessionShutdown.then((_) async {
      try {
        await _stopLocalCapture();
      } on Object {
        // Native capture/playback cleanup must not skip host stop.
      }
      try {
        if (await _client.isSupported()) {
          status = await _client.stop();
        }
      } on Object {
        // Best-effort host stop after local capture shutdown.
      }
    });
    _sessionShutdown = shutdown.catchError((Object _) {});
    await _sessionShutdown;
    if (token != _stopToken) {
      return;
    }
    if (status != null) {
      state = status!;
    }
  }

  Future<void> _awaitSettledShutdown() async {
    await _sessionShutdown;
    await _teardown;
  }

  int _beginLocalShutdown() {
    _stopToken += 1;
    _playbackEnabled = false;
    return _stopToken;
  }

  Future<void> _onTransportLost() async {
    final token = _beginLocalShutdown();
    try {
      await _stopLocalCapture();
    } on Object {
      // Capture cleanup must not surface as an unhandled disconnect error.
    }
    if (token != _stopToken) {
      return;
    }
    state = state.copyWith(
      phase: VoiceSessionPhase.idle,
      lastError: 'The runtime connection closed.',
    );
  }

  Future<void> _stopLocalCapture() async {
    _listening = false;
    _starting = false;
    _playbackEnabled = false;
    _captureEpoch += 1;
    final epoch = _captureEpoch;
    _playbackGeneration += 1;
    _invalidatePlayback();
    _pendingRealtime.clear();
    _realtimeFlushing = false;
    unawaited(_cancelActiveDictation());
    final teardown = () async {
      try {
        await _audio?.stopCapture();
      } on Object {
        // Capture stop must not skip playback stop.
      }
      try {
        await _audio?.stopPlayback();
      } on Object {
        // Playback stop must not skip remaining shutdown.
      }
      if (epoch != _captureEpoch) {
        return;
      }
      _playing = false;
      _streamingPlayback = false;
      _realtimePlayback.clear();
    }();
    _teardown = _teardown.then((_) => teardown).catchError((Object _) {});
    await _teardown;
  }

  Future<void> _cancelActiveDictation() async {
    final requestIds = List<String>.of(_activeDictationIds);
    _activeDictationIds.clear();
    for (final requestId in requestIds) {
      try {
        await _nativeDictation?.cancel(requestId);
      } on Object {
        // Best-effort native Whisper cancel.
      }
      try {
        await _runtimeDictation?.cancel(requestId);
      } on Object {
        // Best-effort runtime dictation cancel.
      }
    }
  }

  Future<void> _ensureAudio() async {
    _audio ??= VoiceAudioIo(ref.read(processRunnerProvider));
    _frames ??= _audio!.frames.listen(_onFrame);
  }

  Future<void> _tearDownAudio() async {
    try {
      await _frames?.cancel();
    } on Object {
      // Frame cancellation must not skip audio dispose.
    }
    _frames = null;
    try {
      await _audio?.dispose();
    } on Object {
      // Best-effort audio dispose on controller teardown.
    }
    _audio = null;
  }

  Future<void> _disposeSession(RuntimeVoiceClient client) {
    _beginLocalShutdown();
    final shutdown = _sessionShutdown.then((_) async {
      try {
        await _stopLocalCapture();
      } on Object {
        // Native capture/playback cleanup must not skip host stop.
      }
      try {
        await _tearDownAudio();
      } on Object {
        // Audio dispose must not skip host stop.
      }
      try {
        if (await client.isSupported()) {
          await client.stop();
        }
      } on Object {
        // Best-effort host stop when the desktop voice controller goes away.
      }
    });
    _sessionShutdown = shutdown.catchError((Object _) {});
    return _sessionShutdown;
  }

  void _onEvent(RuntimeHostEvent event) {
    switch (event.name) {
      case aleraRuntimeHostDisconnectedEvent:
        unawaited(_onTransportLost());
      case 'voice.session':
        state = VoiceSessionStatus.fromJson(event.payload);
        _realtime = state.realtime || _realtime;
        if (state.phase == VoiceSessionPhase.idle && _listening) {
          unawaited(_stopLocalCapture());
        }
      case 'voice.utterance':
        if (!_playbackEnabled) {
          return;
        }
        final id = _payloadUtteranceId(event.payload);
        if (id != null && !_invalidPlaybackIds.contains(id)) {
          _admittedPlaybackIds.add(id);
          _rejectUnidentifiedPlayback = false;
        }
        final text = event.payload['text'];
        final realtime = event.payload['realtime'] == true || _realtime;
        if (text is String && text.trim().isNotEmpty && !realtime) {
          _enqueueSpeak(text.trim(), id: id);
        }
      case 'voice.audio':
        if (!_playbackEnabled) {
          return;
        }
        _enqueuePlayback(_onRealtimeAudio, event.payload);
      case 'voice.audioDone':
        if (!_playbackEnabled) {
          return;
        }
        _enqueuePlayback(_flushRealtimePlayback, event.payload);
      case 'voice.interrupt':
        _playbackGeneration += 1;
        _invalidatePlayback(id: _payloadUtteranceId(event.payload));
        unawaited(_audio?.stopPlayback());
        _playing = false;
        _streamingPlayback = false;
        _realtimePlayback.clear();
    }
  }
}
