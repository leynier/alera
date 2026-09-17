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

part 'voice_session_controller.g.dart';

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
class VoiceSessionController extends _$VoiceSessionController {
  StreamSubscription<RuntimeHostEvent>? _events;
  StreamSubscription<VoicePcmFrame>? _frames;
  VoiceAudioIo? _audio;
  final VoiceActivityDetector _vad = VoiceActivityDetector();
  final BytesBuilder _utterance = BytesBuilder(copy: false);
  var _listening = false;
  var _starting = false;
  var _playbackEnabled = false;
  final List<Int16List> _vadPreroll = <Int16List>[];
  var _playing = false;
  var _realtime = false;
  var _streamingPlayback = false;
  final BytesBuilder _realtimePlayback = BytesBuilder(copy: false);
  var _realtimeSampleRate = 24000;
  Future<void> _realtimeSends = Future<void>.value();
  Future<void> _playbackSends = Future<void>.value();
  Future<void> _speakChain = Future<void>.value();
  Future<void> _turnChain = Future<void>.value();
  Future<void> _teardown = Future<void>.value();
  Future<void> _sessionShutdown = Future<void>.value();
  var _realtimeFlushing = false;
  var _playbackGeneration = 0;
  var _captureEpoch = 0;
  var _stopToken = 0;
  int? _activePlaybackId;
  var _rejectUnidentifiedPlayback = false;
  final Set<int> _invalidPlaybackIds = <int>{};
  final Set<int> _admittedPlaybackIds = <int>{};
  final Set<String> _activeDictationIds = <String>{};
  NativeAiDictationProvider? _nativeDictation;
  RuntimeAiDictationProvider? _runtimeDictation;
  final List<_VoiceRealtimeOp> _pendingRealtime = <_VoiceRealtimeOp>[];

  RuntimeVoiceClient get _client => ref.read(runtimeVoiceClientProvider);

  VoiceSettings get _settings => ref.read(settingsControllerProvider).voice;

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

  void _onFrame(VoicePcmFrame frame) {
    if (!_listening) {
      return;
    }
    final event = _vad.observe(frame.rms, speaking: _playing);
    switch (event) {
      case VoiceActivityEvent.speechStart:
        _playbackGeneration += 1;
        _invalidatePlayback();
        unawaited(_audio?.stopPlayback());
        _playing = false;
        _streamingPlayback = false;
        _realtimePlayback.clear();
        if (!_realtime) {
          unawaited(_client.sendActivity('start'));
        }
        _utterance.clear();
        for (final preroll in _vadPreroll) {
          _appendPcm(preroll);
        }
        _vadPreroll.clear();
        _appendPcm(frame.samples);
        if (_realtime) {
          final pcm = _utterance.takeBytes();
          _utterance.add(pcm);
          _queueRealtimeStart(pcm);
        }
      case VoiceActivityEvent.none:
        if (_vad.capturing) {
          _appendPcm(frame.samples);
          if (_realtime) {
            _queueRealtimeAudio(_pcmBytes(frame.samples));
          }
        } else {
          _vadPreroll.add(Int16List.fromList(frame.samples));
          if (_vadPreroll.length > 4) {
            _vadPreroll.removeAt(0);
          }
        }
      case VoiceActivityEvent.speechEnd:
        _appendPcm(frame.samples);
        final pcm = _utterance.takeBytes();
        if (_realtime) {
          _queueRealtimeEnd(_pcmBytes(frame.samples));
        } else {
          _enqueueTurn(pcm);
        }
    }
  }

  List<int> _pcmBytes(Int16List samples) {
    return Uint8List.view(
      samples.buffer,
      samples.offsetInBytes,
      samples.lengthInBytes,
    );
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
              for (final op in batch) {
                if (epoch != _captureEpoch) {
                  return;
                }
                switch (op) {
                  case _VoiceRealtimeStart():
                    await _client.sendActivity('start');
                  case _VoiceRealtimeAudio(:final pcm):
                    if (pcm.isNotEmpty) {
                      await _client.sendAudio(pcm);
                    }
                  case _VoiceRealtimeEnd():
                    await _client.sendActivity('end');
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

  void _enqueueTurn(List<int> pcm) {
    final epoch = _captureEpoch;
    _turnChain = _turnChain
        .then((_) async {
          if (epoch != _captureEpoch) {
            return;
          }
          await _submitUtterance(pcm, epoch: epoch);
        })
        .catchError((Object _) {});
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
          await _speak(text, id: id, generation: generation, epoch: epoch);
        })
        .catchError((Object _) {});
  }

  void _appendPcm(Int16List samples) {
    _utterance.add(
      Uint8List.view(
        samples.buffer,
        samples.offsetInBytes,
        samples.lengthInBytes,
      ),
    );
  }

  Future<void> _submitUtterance(List<int> pcm, {required int epoch}) async {
    if (pcm.isEmpty || epoch != _captureEpoch) {
      return;
    }
    try {
      if (_settings.sttProvider == VoiceSttProvider.geminiTranscribeLive) {
        await _client.submitTurn('', pcm16k: pcm);
        if (epoch != _captureEpoch) {
          return;
        }
        await refresh();
        return;
      }
      final text = await _transcribe(pcm, epoch: epoch);
      if (epoch != _captureEpoch) {
        return;
      }
      final trimmed = text.trim();
      if (trimmed.isEmpty) {
        return;
      }
      await _client.submitTurn(
        trimmed,
        cancelHome: looksLikeHomeCancel(trimmed),
      );
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

  Future<String> _transcribe(List<int> pcm, {required int epoch}) async {
    final wav = pcm16ToWav(pcm);
    final private = await VoicePrivateWav.write(wav, prefix: 'alera-voice-turn');
    final requestId = 'voice-${const Uuid().v4()}';
    _activeDictationIds.add(requestId);
    try {
      if (epoch != _captureEpoch) {
        return '';
      }
      final settings = _settings;
      final dictation = ref.read(settingsControllerProvider).aiDictation;
      final request = AiDictationRequest(
        requestId: requestId,
        audioPath: private.path,
        modelPath: settings.sttProvider == VoiceSttProvider.localWhisper
            ? await ref
                  .read(aiDictationModelStoreProvider)
                  .modelPath(dictation.localModelId)
            : null,
        language: dictation.language,
        remoteEngine: switch (settings.sttProvider) {
          VoiceSttProvider.codexRealtime =>
            AiDictationRemoteEngine.codexSubscription,
          VoiceSttProvider.openAiCompatible =>
            AiDictationRemoteEngine.openAiCompatible,
          VoiceSttProvider.geminiTranscribeLive ||
          VoiceSttProvider.localWhisper => null,
        },
        providerBaseUrl: dictation.remoteBaseUrl,
        providerModel: dictation.remoteModel,
        timeout: const Duration(seconds: 60),
      );
      if (epoch != _captureEpoch) {
        return '';
      }
      final result = settings.sttProvider == VoiceSttProvider.localWhisper
          ? await (_nativeDictation ??= NativeAiDictationProvider()).transcribe(
              request,
            )
          : await (_runtimeDictation ??= RuntimeAiDictationProvider(
              ref.read(runtimeHostClientProvider),
            )).transcribe(request);
      if (epoch != _captureEpoch) {
        return '';
      }
      return result.text;
    } finally {
      _activeDictationIds.remove(requestId);
      await private.delete();
    }
  }

  Future<void> _speak(
    String text, {
    int? id,
    required int generation,
    required int epoch,
  }) async {
    try {
      final audio = await _client.synthesize(
        text,
        provider: _settings.ttsProvider.name,
        voice: _settings.ttsVoice,
      );
      if (generation != _playbackGeneration || epoch != _captureEpoch) {
        return;
      }
      if (audio.isEmpty) {
        throw StateError('Voice synthesis returned no audio.');
      }
      _playing = true;
      await _audio?.playWav(audio);
      if (generation != _playbackGeneration || epoch != _captureEpoch) {
        return;
      }
      _playing = false;
      await _client.markSpoken(text, id: id);
      await refresh();
    } on Object catch (error) {
      if (generation != _playbackGeneration || epoch != _captureEpoch) {
        return;
      }
      _playing = false;
      try {
        await _client.markSpoken(text, id: id, failed: true, error: error.toString());
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
        await _audio?.startPcmStream(sampleRate: _realtimeSampleRate);
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
      if (generation != _playbackGeneration || epoch != _captureEpoch) {
        await _audio?.stopPlayback();
        return;
      }
      _streamingPlayback = _audio?.isStreaming == true;
    }
    if (generation != _playbackGeneration || epoch != _captureEpoch) {
      return;
    }
    if (_streamingPlayback) {
      try {
        await _audio?.writePcm(pcm);
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
        await _audio?.finishPcmStream();
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
      _playing = false;
      _retirePlaybackId(utteranceId);
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
      _playing = true;
      await _audio?.playPcm(pcm, sampleRate: _realtimeSampleRate);
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
    await _client.markSpoken(spoken, id: id, failed: failed, error: error);
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
      await _audio?.stopPlayback();
    } on Object {
      // Native stop must not skip retiring the failed host utterance.
    }
    if (generation != _playbackGeneration || epoch != _captureEpoch) {
      return;
    }
    try {
      await _ackSpoken(text, id: utteranceId, failed: true, error: error.toString());
    } on Object {
      if (generation != _playbackGeneration || epoch != _captureEpoch) {
        return;
      }
      state = state.copyWith(lastError: error.toString());
    }
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
