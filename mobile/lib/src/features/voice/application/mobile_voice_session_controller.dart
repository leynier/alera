import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:alera_mobile/src/features/voice/application/mobile_voice_session_state.dart';
import 'package:alera_mobile/src/features/voice/domain/voice_activity_detector.dart';
import 'package:alera_mobile/src/features/voice/infra/mobile_voice_audio.dart';
import 'package:alera_mobile/src/features/voice/infra/mobile_voice_capture.dart';
import 'package:alera_mobile/src/features/voice/infra/voice_pcm_player.dart';
import 'package:just_audio/just_audio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

export 'package:alera_mobile/src/features/voice/application/mobile_voice_session_state.dart';

part 'mobile_voice_session_capture.dart';
part 'mobile_voice_session_controller.g.dart';
part 'mobile_voice_session_fields.dart';
part 'mobile_voice_session_playback.dart';

@riverpod
class MobileVoiceSessionController extends _$MobileVoiceSessionController
    with
        _MobileVoiceSessionFields,
        _MobileVoiceSessionPlayback,
        _MobileVoiceSessionCapture {
  @override
  MobileVoiceSessionState build(String hostId) {
    ref.onDispose(() {
      unawaited(_events?.cancel());
      unawaited(_tearDown());
    });
    unawaited(refresh());
    return const MobileVoiceSessionState();
  }

  Future<void> _bindClient(MobileRuntimeClient client) async {
    if (identical(_retainedClient, client) && _events != null) {
      return;
    }
    final generation = ++_bindGeneration;
    await _events?.cancel();
    if (!ref.mounted || generation != _bindGeneration) {
      return;
    }
    if (identical(_retainedClient, client) && _events != null) {
      return;
    }
    _retainedClient = client;
    final bound = client;
    _events = client.events.listen(
      _onEvent,
      onDone: () {
        if (!identical(_retainedClient, bound)) {
          return;
        }
        unawaited(_onTransportLost());
      },
    );
  }

  @override
  Future<void> refresh() async {
    try {
      if (!ref.mounted) {
        return;
      }
      final client = await _liveClient();
      if (!ref.mounted) {
        return;
      }
      if (!client.supportsVoiceHomeAgent) {
        state = const MobileVoiceSessionState(
          lastError: 'Update the paired runtime to use the voice home agent.',
        );
        return;
      }
      await _bindClient(client);
      if (!ref.mounted) {
        return;
      }
      final status = await client.voiceStatus();
      if (!ref.mounted) {
        return;
      }
      state = _fromStatus(
        status,
        supported: true,
        active: state.active,
        busy: state.busy,
      );
    } on Object catch (error) {
      if (!ref.mounted) {
        return;
      }
      state = MobileVoiceSessionState(lastError: error.toString());
    }
  }

  Future<void> toggle() async {
    if (state.active) {
      await stop();
    } else {
      await start();
    }
  }

  Future<void> start() async {
    if (_listening || _starting || state.busy) {
      return;
    }
    _starting = true;
    final intent = _beginLocalShutdown();
    var epoch = _captureEpoch;
    state = MobileVoiceSessionState(
      supported: state.supported,
      active: state.active,
      busy: true,
      phase: state.phase,
      realtime: state.realtime,
      queuedSpeakCount: state.queuedSpeakCount,
      queuedTurnCount: state.queuedTurnCount,
      lastSpoken: state.lastSpoken,
      lastError: state.lastError,
    );
    try {
      await _sessionShutdown;
      await _teardown;
      if (intent != _stopToken || _listening) {
        return;
      }
      _captureEpoch += 1;
      epoch = _captureEpoch;
      final client = await _liveClient();
      if (!ref.mounted || intent != _stopToken || epoch != _captureEpoch) {
        return;
      }
      if (!client.supportsVoiceHomeAgent) {
        throw UnsupportedError(
          'Update the paired runtime to use the voice home agent.',
        );
      }
      await _bindClient(client);
      if (!ref.mounted || intent != _stopToken || epoch != _captureEpoch) {
        return;
      }
      final status = await client.startVoice(
        stillValid: () => intent == _stopToken && epoch == _captureEpoch,
      );
      if (status == null || intent != _stopToken || epoch != _captureEpoch) {
        return;
      }
      _playbackEnabled = true;
      _playbackGeneration += 1;
      _realtime =
          status['realtime'] == true ||
          (status['settings'] is Map &&
              (status['settings'] as Map)['pipeline'] == 'realtime');
      await _startCapture(epoch);
      if (epoch != _captureEpoch) {
        return;
      }
      _vad.reset();
      _vadPreroll.clear();
      _pcmRemainder.clear();
      _utterance.clear();
      _pendingRealtime.clear();
      _realtimeFlushing = false;
      _realtimePlayback.clear();
      _streamingPlayback = false;
      _playbackSends = Future<void>.value();
      _speakChain = Future<void>.value();
      _activePlaybackId = null;
      _rejectUnidentifiedPlayback = false;
      _invalidPlaybackIds.clear();
      _admittedPlaybackIds.clear();
      _listening = true;
      _starting = false;
      if (!ref.mounted) {
        return;
      }
      state = _fromStatus(status, supported: true, active: true, busy: false);
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
    Map<String, Object?>? status;
    final shutdown = _sessionShutdown.then((_) async {
      try {
        await _stopLocalCapture();
      } on Object {
        // Native capture/playback cleanup must not skip host stop.
      }
      try {
        final client = await _client();
        if (client.supportsVoiceHomeAgent) {
          status = await client.stopVoice();
        }
      } on Object {
        // Best-effort host rollback after a failed microphone start.
      }
    });
    _sessionShutdown = shutdown.catchError((Object _) {});
    final client = _retainedClient;
    client?.registerVoiceSessionShutdown(_sessionShutdown);
    await _sessionShutdown;
    if (token != _stopToken) {
      return;
    }
    state = MobileVoiceSessionState(
      supported: state.supported,
      lastError: error.toString(),
    );
    if (status != null) {
      state = _fromStatus(
        status!,
        supported: true,
        active: false,
        busy: false,
      ).copyWith(lastError: error.toString());
    }
  }

  Future<void> stop() async {
    final token = _beginLocalShutdown();
    Map<String, Object?>? status;
    Object? stopError;
    final shutdown = _sessionShutdown.then((_) async {
      try {
        await _stopLocalCapture();
      } on Object {
        // Native capture/playback cleanup must not skip host stop.
      }
      try {
        final client = await _client();
        if (client.supportsVoiceHomeAgent) {
          status = await client.stopVoice();
        }
      } on Object catch (error) {
        stopError = error;
      }
    });
    _sessionShutdown = shutdown.catchError((Object _) {});
    final client = _retainedClient;
    client?.registerVoiceSessionShutdown(_sessionShutdown);
    await _sessionShutdown;
    if (token != _stopToken) {
      return;
    }
    if (stopError != null) {
      state = MobileVoiceSessionState(lastError: stopError.toString());
      return;
    }
    if (status != null) {
      state = _fromStatus(status!, supported: true, active: false, busy: false);
      return;
    }
    state = const MobileVoiceSessionState(supported: true);
  }

  int _beginLocalShutdown() {
    _stopToken += 1;
    _playbackEnabled = false;
    return _stopToken;
  }

  Future<void> _stopLocalCapture() async {
    await _stopOwnedCapture(_captureEpoch);
  }

  Future<void> _onTransportLost() async {
    final lost = _retainedClient;
    if (!identical(_retainedClient, lost)) {
      return;
    }
    final token = _beginLocalShutdown();
    try {
      await _stopLocalCapture();
    } on Object {
      // Capture cleanup must not surface as an unhandled disconnect error.
    }
    if (token != _stopToken) {
      return;
    }
    if (!identical(_retainedClient, lost)) {
      return;
    }
    _retainedClient = null;
    state = state.copyWith(
      active: false,
      busy: false,
      phase: 'idle',
      lastError: 'The runtime connection closed.',
    );
  }

  void _onEvent(MobileRuntimeEvent event) {
    switch (event.name) {
      case 'voice.session':
        state = _fromStatus(
          event.payload,
          supported: true,
          active: state.active,
          busy: state.busy,
        );
        _realtime = event.payload['realtime'] == true || _realtime;
        if ((event.payload['phase'] as String? ?? 'idle') == 'idle' &&
            _listening) {
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
        unawaited(_stopPlayback());
        _playing = false;
        _streamingPlayback = false;
        _realtimePlayback.clear();
    }
  }

  Future<void> _tearDown() {
    _beginLocalShutdown();
    _bindGeneration += 1;
    final client = _retainedClient;
    final shutdown = _sessionShutdown.then((_) async {
      try {
        await _stopLocalCapture();
      } on Object {
        // Native capture/playback cleanup must not skip host stop.
      }
      try {
        await _capture.dispose();
      } on Object {
        // Recorder dispose must not skip player dispose.
      }
      try {
        await _player?.dispose();
      } on Object {
        // Player dispose must not skip PCM stop.
      }
      _player = null;
      try {
        await _pcm.stop();
      } on Object {
        // PCM stop must not skip host stop.
      }
      if (client == null || !client.supportsVoiceHomeAgent) {
        return;
      }
      try {
        await client.stopVoice();
      } on Object {
        // Best-effort host stop when the screen or connection goes away.
      }
    });
    _sessionShutdown = shutdown.catchError((Object _) {});
    client?.registerVoiceSessionShutdown(_sessionShutdown);
    return _sessionShutdown;
  }
}
