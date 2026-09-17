import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:alera_mobile/src/features/voice/domain/voice_activity_detector.dart';
import 'package:alera_mobile/src/features/voice/infra/mobile_voice_audio.dart';
import 'package:alera_mobile/src/features/voice/infra/voice_pcm_player.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mobile_voice_session_controller.g.dart';

class const MobileVoiceSessionState({
  this.supported = false,
  this.active = false,
  this.busy = false,
  this.phase = 'idle',
  this.realtime = false,
  this.queuedSpeakCount = 0,
  this.queuedTurnCount = 0,
  this.lastSpoken,
  this.lastError,
}) {
  final bool supported;
  final bool active;
  final bool busy;
  final String phase;
  final bool realtime;
  final int queuedSpeakCount;
  final int queuedTurnCount;
  final String? lastSpoken;
  final String? lastError;

  MobileVoiceSessionState copyWith({
    bool? supported,
    bool? active,
    bool? busy,
    String? phase,
    bool? realtime,
    int? queuedSpeakCount,
    int? queuedTurnCount,
    String? lastSpoken,
    String? lastError,
  }) {
    return MobileVoiceSessionState(
      supported: supported ?? this.supported,
      active: active ?? this.active,
      busy: busy ?? this.busy,
      phase: phase ?? this.phase,
      realtime: realtime ?? this.realtime,
      queuedSpeakCount: queuedSpeakCount ?? this.queuedSpeakCount,
      queuedTurnCount: queuedTurnCount ?? this.queuedTurnCount,
      lastSpoken: lastSpoken ?? this.lastSpoken,
      lastError: lastError ?? this.lastError,
    );
  }
}

@riverpod
class MobileVoiceSessionController extends _$MobileVoiceSessionController {
  StreamSubscription<MobileRuntimeEvent>? _events;
  StreamSubscription<Uint8List>? _frames;
  AudioRecorder? _recorder;
  AudioPlayer? _player;
  final VoicePcmPlayer _pcm = VoicePcmPlayer();
  final VoiceActivityDetector _vad = VoiceActivityDetector();
  final BytesBuilder _utterance = BytesBuilder(copy: false);
  var _listening = false;
  var _playbackEnabled = false;
  final List<Int16List> _vadPreroll = <Int16List>[];
  final BytesBuilder _pcmRemainder = BytesBuilder(copy: false);
  var _starting = false;
  var _playing = false;
  var _realtime = false;
  var _streamingPlayback = false;
  final BytesBuilder _realtimePlayback = BytesBuilder(copy: false);
  var _realtimeSampleRate = 24000;
  Future<void> _realtimeSends = Future<void>.value();
  Future<void> _playbackSends = Future<void>.value();
  Future<void> _speakChain = Future<void>.value();
  Future<void> _teardown = Future<void>.value();
  Future<void> _sessionShutdown = Future<void>.value();
  var _realtimeFlushing = false;
  var _playbackGeneration = 0;
  var _captureEpoch = 0;
  var _stopToken = 0;
  var _recorderGeneration = 0;
  int? _activePlaybackId;
  var _rejectUnidentifiedPlayback = false;
  final Set<int> _invalidPlaybackIds = <int>{};
  final Set<int> _admittedPlaybackIds = <int>{};
  MobileRuntimeClient? _retainedClient;
  var _bindGeneration = 0;
  final List<_VoiceRealtimeOp> _pendingRealtime = <_VoiceRealtimeOp>[];

  @override
  MobileVoiceSessionState build(String hostId) {
    ref.onDispose(() {
      unawaited(_events?.cancel());
      unawaited(_tearDown());
    });
    unawaited(refresh());
    return const MobileVoiceSessionState();
  }

  Future<MobileRuntimeClient> _liveClient() {
    return ref.read(hostConnectionControllerProvider(hostId).future);
  }

  Future<MobileRuntimeClient> _client() async {
    return _retainedClient ?? await _liveClient();
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
      state = _fromStatus(
        status,
        supported: true,
        active: true,
        busy: false,
      );
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
      state = _fromStatus(
        status!,
        supported: true,
        active: false,
        busy: false,
      );
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

  Future<void> _stopOwnedCapture(int epoch) async {
    if (epoch != _captureEpoch) {
      return;
    }
    _listening = false;
    _starting = false;
    _playbackEnabled = false;
    _captureEpoch += 1;
    final owned = _captureEpoch;
    _playbackGeneration += 1;
    _invalidatePlayback();
    _pendingRealtime.clear();
    _realtimeFlushing = false;
    _pcmRemainder.clear();
    final frames = _frames;
    _frames = null;
    final teardown = () async {
      try {
        await frames?.cancel();
      } on Object {
        // Frame cancellation must not skip recorder stop.
      }
      try {
        await _recorder?.stop();
      } on Object {
        // Recorder stop must not skip playback stop.
      }
      try {
        await _stopPlayback();
      } on Object {
        // Playback stop must not skip remaining shutdown.
      }
      if (owned != _captureEpoch) {
        return;
      }
      _playing = false;
    }();
    _teardown = _teardown.then((_) => teardown).catchError((Object _) {});
    await _teardown;
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

  Future<void> _startCapture(int epoch) async {
    final recorder = _recorder ??= AudioRecorder();
    if (!await recorder.hasPermission()) {
      throw StateError('Microphone permission is required for voice.');
    }
    if (epoch != _captureEpoch) {
      return;
    }
    final stream = await recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    if (epoch != _captureEpoch) {
      return;
    }
    _recorderGeneration += 1;
    final recorderGeneration = _recorderGeneration;
    await _frames?.cancel();
    _frames = stream.listen(_onBytes);
    if (epoch != _captureEpoch || recorderGeneration != _recorderGeneration) {
      await _frames?.cancel();
      _frames = null;
      if (recorderGeneration == _recorderGeneration) {
        await recorder.stop();
      }
    }
  }

  void _onBytes(Uint8List chunk) {
    if (!_listening || chunk.isEmpty) {
      return;
    }
    const bytesPerFrame = 640;
    _pcmRemainder.add(chunk);
    var buffer = _pcmRemainder.takeBytes();
    var offset = 0;
    while (buffer.length - offset >= bytesPerFrame) {
      final frameBytes = Uint8List.sublistView(
        buffer,
        offset,
        offset + bytesPerFrame,
      );
      offset += bytesPerFrame;
      _onFixedFrame(pcmFrameFromBytes(frameBytes));
    }
    if (offset < buffer.length) {
      _pcmRemainder.add(Uint8List.sublistView(buffer, offset));
    }
  }

  void _onFixedFrame(MobileVoicePcmFrame frame) {
    final event = _vad.observe(frame.rms, speaking: _playing);
    switch (event) {
      case VoiceActivityEvent.speechStart:
        _playbackGeneration += 1;
        _invalidatePlayback();
        unawaited(_stopPlayback());
        _playing = false;
        _streamingPlayback = false;
        _realtimePlayback.clear();
        if (!_realtime) {
          _enqueueChainedBargeIn();
        }
        _utterance.clear();
        for (final preroll in _vadPreroll) {
          _append(preroll);
        }
        _vadPreroll.clear();
        _append(frame.samples);
        if (_realtime) {
          final pcm = _utterance.takeBytes();
          _utterance.add(pcm);
          _queueRealtimeStart(pcm);
        }
      case VoiceActivityEvent.none:
        if (_vad.capturing) {
          _append(frame.samples);
          if (_realtime) {
            _queueRealtimeAudio(pcmBytes(frame.samples));
          }
        } else {
          _vadPreroll.add(Int16List.fromList(frame.samples));
          if (_vadPreroll.length > 4) {
            _vadPreroll.removeAt(0);
          }
        }
      case VoiceActivityEvent.speechEnd:
        _append(frame.samples);
        final pcm = _utterance.takeBytes();
        if (_realtime) {
          _queueRealtimeEnd(pcmBytes(frame.samples));
        } else {
          unawaited(_submitUtterance(pcm, epoch: _captureEpoch));
        }
    }
  }

  void _append(Int16List samples) {
    _utterance.add(pcmBytes(samples));
  }

  void _enqueueChainedBargeIn() {
    final epoch = _captureEpoch;
    _realtimeSends = _realtimeSends
        .then((_) async {
          if (epoch != _captureEpoch) {
            return;
          }
          final client = await _client();
          if (epoch != _captureEpoch) {
            return;
          }
          await client.sendVoiceActivity('start');
        })
        .catchError((Object _) {});
  }

  void _queueRealtimeStart(List<int> pcm) {
    _pendingRealtime.add(const _VoiceRealtimeOp.start());
    if (pcm.isNotEmpty) {
      _pendingRealtime.add(_VoiceRealtimeOp.audio(pcm));
    }
    _scheduleRealtimeFlush();
  }

  void _queueRealtimeAudio(List<int> pcm) {
    if (pcm.isEmpty) {
      return;
    }
    final last = _pendingRealtime.isEmpty ? null : _pendingRealtime.last;
    if (last is _VoiceRealtimeAudio) {
      last.pcm.addAll(pcm);
    } else {
      _pendingRealtime.add(_VoiceRealtimeOp.audio(pcm));
    }
    _scheduleRealtimeFlush();
  }

  void _queueRealtimeEnd(List<int> pcm) {
    if (pcm.isNotEmpty) {
      _queueRealtimeAudio(pcm);
    }
    _pendingRealtime.add(const _VoiceRealtimeOp.end());
    _scheduleRealtimeFlush();
  }

  void _scheduleRealtimeFlush() {
    if (_realtimeFlushing) {
      return;
    }
    _realtimeFlushing = true;
    final epoch = _captureEpoch;
    _realtimeSends = _realtimeSends
        .then((_) async {
          try {
            while (epoch == _captureEpoch) {
              if (_pendingRealtime.isEmpty) {
                break;
              }
              final batch = List<_VoiceRealtimeOp>.of(_pendingRealtime);
              _pendingRealtime.clear();
              final client = await _client();
              if (epoch != _captureEpoch) {
                return;
              }
              for (final op in batch) {
                if (epoch != _captureEpoch) {
                  return;
                }
                switch (op) {
                  case _VoiceRealtimeStart():
                    await client.sendVoiceActivity('start');
                  case _VoiceRealtimeAudio(:final pcm):
                    if (pcm.isNotEmpty) {
                      await client.sendVoiceAudio(pcm);
                    }
                  case _VoiceRealtimeEnd():
                    await client.sendVoiceActivity('end');
                }
              }
            }
          } finally {
            if (epoch == _captureEpoch) {
              _realtimeFlushing = false;
              if (_pendingRealtime.isNotEmpty) {
                _scheduleRealtimeFlush();
              }
            }
          }
        })
        .catchError((Object _) {});
  }

  void _enqueuePlayback(
    Future<void> Function(
      Map<String, Object?> payload,
      int generation,
      int epoch,
    )
    work,
    Map<String, Object?> payload,
  ) {
    final epoch = _captureEpoch;
    final generation = _playbackGeneration;
    final utteranceId = _payloadUtteranceId(payload);
    _playbackSends = _playbackSends
        .then((_) async {
          if (epoch != _captureEpoch ||
              generation != _playbackGeneration ||
              !_acceptsPlaybackId(utteranceId)) {
            return;
          }
          await work(payload, generation, epoch);
        })
        .catchError((Object _) {});
  }

  int? _payloadUtteranceId(Map<String, Object?> payload) {
    final id = payload['id'];
    return id is num ? id.toInt() : null;
  }

  void _invalidatePlayback({int? id}) {
    if (id != null) {
      _invalidPlaybackIds.add(id);
      _admittedPlaybackIds.remove(id);
      if (_activePlaybackId == id) {
        _activePlaybackId = null;
      }
      return;
    }
    _invalidPlaybackIds.addAll(_admittedPlaybackIds);
    final active = _activePlaybackId;
    if (active != null) {
      _invalidPlaybackIds.add(active);
    }
    _admittedPlaybackIds.clear();
    _activePlaybackId = null;
    _rejectUnidentifiedPlayback = true;
  }

  void _retirePlaybackId(int? id) {
    if (id != null && _activePlaybackId == id) {
      _activePlaybackId = null;
    }
    if (id != null) {
      _admittedPlaybackIds.remove(id);
    }
  }

  bool _acceptsPlaybackId(int? id) {
    if (!_playbackEnabled) {
      return false;
    }
    if (id == null) {
      return !_rejectUnidentifiedPlayback &&
          _activePlaybackId == null &&
          _invalidPlaybackIds.isEmpty;
    }
    if (_invalidPlaybackIds.contains(id)) {
      return false;
    }
    if (_rejectUnidentifiedPlayback) {
      return _admittedPlaybackIds.contains(id) || _activePlaybackId == id;
    }
    final active = _activePlaybackId;
    return active == null || active == id;
  }

  void _enqueueSpeak(String text, {int? id}) {
    final epoch = _captureEpoch;
    final generation = _playbackGeneration;
    _speakChain = _speakChain
        .then((_) async {
          if (epoch != _captureEpoch ||
              generation != _playbackGeneration ||
              !_playbackEnabled) {
            return;
          }
          await _speakChained(
            text,
            id: id,
            generation: generation,
            epoch: epoch,
          );
        })
        .catchError((Object _) {});
  }

  Future<void> _submitUtterance(List<int> pcm, {required int epoch}) async {
    if (pcm.isEmpty || epoch != _captureEpoch) {
      return;
    }
    try {
      final client = await _client();
      await client.submitVoiceTurn('', pcm16k: pcm);
      if (epoch != _captureEpoch) {
        return;
      }
      await refresh();
    } on Object catch (error) {
      if (epoch != _captureEpoch) {
        return;
      }
      state = state.copyWith(lastError: error.toString());
    }
  }

  Future<void> _speakChained(
    String text, {
    int? id,
    required int generation,
    required int epoch,
  }) async {
    try {
      final client = await _client();
      final audio = await client.synthesizeVoice(text);
      if (generation != _playbackGeneration || epoch != _captureEpoch) {
        return;
      }
      if (audio.isEmpty) {
        throw StateError('Voice synthesis returned no audio.');
      }
      _playing = true;
      final player = _player ??= AudioPlayer();
      await player.setUrl(
        Uri.dataFromBytes(audio, mimeType: 'audio/wav').toString(),
      );
      if (generation != _playbackGeneration || epoch != _captureEpoch) {
        await player.stop();
        return;
      }
      await player.play();
      if (generation != _playbackGeneration || epoch != _captureEpoch) {
        return;
      }
      await client.markVoiceSpoken(text, id: id);
      _playing = false;
      await refresh();
    } on Object catch (error) {
      if (generation != _playbackGeneration || epoch != _captureEpoch) {
        return;
      }
      _playing = false;
      try {
        final client = await _client();
        if (generation != _playbackGeneration || epoch != _captureEpoch) {
          return;
        }
        await client.markVoiceSpoken(
          text,
          id: id,
          failed: true,
          error: error.toString(),
        );
        await refresh();
      } on Object {
        state = state.copyWith(lastError: error.toString());
      }
    }
  }

  Future<void> _onRealtimeAudio(
    Map<String, Object?> payload,
    int generation,
    int epoch,
  ) async {
    final utteranceId = _payloadUtteranceId(payload);
    if (!_acceptsPlaybackId(utteranceId)) {
      return;
    }
    if (utteranceId != null) {
      _activePlaybackId = utteranceId;
    }
    final encoded = payload['audioBase64'];
    if (encoded is! String || encoded.isEmpty) {
      return;
    }
    final pcm = base64Decode(encoded);
    final sampleRate = payload['sampleRate'];
    if (sampleRate is num) {
      _realtimeSampleRate = sampleRate.toInt();
    }
    _playing = true;
    if (!_streamingPlayback) {
      try {
        await _pcm.start(sampleRate: _realtimeSampleRate);
        if (generation != _playbackGeneration || epoch != _captureEpoch) {
          await _pcm.stop();
          return;
        }
        _streamingPlayback = _pcm.isStreaming;
      } on Object catch (error) {
        await _failRealtimePlayback(
          utteranceId: utteranceId,
          text: null,
          error: error,
          generation: generation,
          epoch: epoch,
        );
        return;
      }
    }
    if (generation != _playbackGeneration || epoch != _captureEpoch) {
      return;
    }
    if (_streamingPlayback) {
      try {
        _pcm.write(pcm);
      } on Object catch (error) {
        await _failRealtimePlayback(
          utteranceId: utteranceId,
          text: null,
          error: error,
          generation: generation,
          epoch: epoch,
        );
      }
      return;
    }
    _realtimePlayback.add(pcm);
  }

  Future<void> _flushRealtimePlayback(
    Map<String, Object?> payload,
    int generation,
    int epoch,
  ) async {
    final utteranceId = _payloadUtteranceId(payload);
    if (!_acceptsPlaybackId(utteranceId)) {
      return;
    }
    final spoken = payload['text'];
    final text = spoken is String ? spoken : null;
    final id = payload['id'];
    if (_streamingPlayback) {
      try {
        _pcm.finish();
        await _pcm.waitUntilDone();
      } on Object catch (error) {
        await _failRealtimePlayback(
          utteranceId: utteranceId,
          text: text,
          error: error,
          generation: generation,
          epoch: epoch,
        );
        return;
      }
      if (generation != _playbackGeneration || epoch != _captureEpoch) {
        return;
      }
      _streamingPlayback = false;
      _playing = false;
      _retirePlaybackId(utteranceId);
      await _ackSpoken(text, id: id is num ? id.toInt() : null);
      return;
    }
    final pcm = _realtimePlayback.takeBytes();
    if (pcm.isEmpty) {
      await _failRealtimePlayback(
        utteranceId: utteranceId,
        text: text,
        error: StateError('Realtime playback received no audio.'),
        generation: generation,
        epoch: epoch,
      );
      return;
    }
    try {
      final wav = pcm16ToWav(pcm, sampleRate: _realtimeSampleRate);
      final player = _player ??= AudioPlayer();
      _playing = true;
      await player.setUrl(
        Uri.dataFromBytes(wav, mimeType: 'audio/wav').toString(),
      );
      if (generation != _playbackGeneration || epoch != _captureEpoch) {
        await player.stop();
        return;
      }
      await player.play();
      if (generation != _playbackGeneration || epoch != _captureEpoch) {
        return;
      }
      _playing = false;
      _retirePlaybackId(utteranceId);
      await _ackSpoken(text, id: id is num ? id.toInt() : null);
    } on Object catch (error) {
      await _failRealtimePlayback(
        utteranceId: utteranceId,
        text: text,
        error: error,
        generation: generation,
        epoch: epoch,
      );
    }
  }

  Future<void> _ackSpoken(
    String? text, {
    int? id,
    bool failed = false,
    String? error,
  }) async {
    final spoken = text?.trim() ?? '';
    if (spoken.isEmpty && !failed) {
      return;
    }
    final client = await _client();
    await client.markVoiceSpoken(spoken, id: id, failed: failed, error: error);
    await refresh();
  }

  Future<void> _failRealtimePlayback({
    required int? utteranceId,
    required String? text,
    required Object error,
    required int generation,
    required int epoch,
  }) async {
    if (generation != _playbackGeneration || epoch != _captureEpoch) {
      return;
    }
    _playing = false;
    _streamingPlayback = false;
    _realtimePlayback.clear();
    _retirePlaybackId(utteranceId);
    _invalidatePlayback(id: utteranceId);
    try {
      await _stopPlayback();
    } on Object {
      // Native stop must not skip retiring the failed host utterance.
    }
    if (generation != _playbackGeneration || epoch != _captureEpoch) {
      return;
    }
    try {
      await _ackSpoken(
        text,
        id: utteranceId,
        failed: true,
        error: error.toString(),
      );
    } on Object {
      if (generation != _playbackGeneration || epoch != _captureEpoch) {
        return;
      }
      state = state.copyWith(lastError: error.toString());
    }
  }

  Future<void> _stopPlayback() async {
    _streamingPlayback = false;
    _realtimePlayback.clear();
    final pcmStop = _pcm.stop();
    try {
      await _player?.stop();
    } on Object {
      // WAV stop must not skip PCM stop.
    }
    try {
      await pcmStop;
    } on Object {
      // PCM stop must not skip remaining shutdown.
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
        await _frames?.cancel();
      } on Object {
        // Frame cancellation must not skip recorder dispose.
      }
      _frames = null;
      try {
        await _recorder?.dispose();
      } on Object {
        // Recorder dispose must not skip player dispose.
      }
      _recorder = null;
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

  MobileVoiceSessionState _fromStatus(
    Map<String, Object?> status, {
    required bool supported,
    required bool active,
    bool busy = false,
  }) {
    return MobileVoiceSessionState(
      supported: supported,
      active: active,
      busy: busy,
      phase: status['phase'] as String? ?? 'idle',
      realtime: status['realtime'] == true,
      queuedSpeakCount: _asInt(status['queuedSpeakCount']),
      queuedTurnCount: _asInt(status['queuedTurnCount']),
      lastSpoken: status['lastSpoken'] as String?,
      lastError: status['lastError'] as String?,
    );
  }

  int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }
}

sealed class _VoiceRealtimeOp {
  const _VoiceRealtimeOp();

  const factory _VoiceRealtimeOp.start() = _VoiceRealtimeStart;

  const factory _VoiceRealtimeOp.end() = _VoiceRealtimeEnd;

  factory _VoiceRealtimeOp.audio(List<int> pcm) = _VoiceRealtimeAudio;
}

final class _VoiceRealtimeStart extends _VoiceRealtimeOp {
  const _VoiceRealtimeStart();
}

final class _VoiceRealtimeEnd extends _VoiceRealtimeOp {
  const _VoiceRealtimeEnd();
}

final class _VoiceRealtimeAudio extends _VoiceRealtimeOp {
  _VoiceRealtimeAudio(List<int> pcm) : pcm = List<int>.of(pcm);

  final List<int> pcm;
}
