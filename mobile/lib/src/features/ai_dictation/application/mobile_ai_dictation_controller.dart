import 'dart:async';
import 'dart:io';

import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_model_transfers.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_state.dart';
import 'package:alera_mobile/src/features/ai_dictation/domain/mobile_ai_dictation_settings.dart';
import 'package:alera_mobile/src/features/ai_dictation/infra/mobile_whisper_transcriber.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

part 'mobile_ai_dictation_controller.g.dart';
part 'mobile_ai_dictation_controller_transcription.dart';

const _capabilityChannel = MethodChannel(
  'dev.leynier.alera/speech_capabilities',
);
const _onlineConsentVersion = 1;
const _remoteConsentVersion = 1;
const _maximumRecordingDuration = Duration(minutes: 2);

@riverpod
Future<bool> mobileAiDictationOnDeviceAvailable(
  Ref ref,
  String? localeId,
) async {
  try {
    return await _capabilityChannel.invokeMethod<bool>(
          'supportsOnDevice',
          <String, Object?>{'localeId': localeId},
        ) ??
        false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

@riverpod
class MobileAiDictationController extends _$MobileAiDictationController {
  final _speech = SpeechToText();
  final _whisper = MobileWhisperTranscriber();
  final _log = Logger('MobileAiDictationController');
  final _subscriptions = <StreamSubscription<Object?>>[];
  AppLifecycleListener? _lifecycleListener;
  var _audioSessionListenersInstalled = false;
  AudioRecorder? _recorder;
  AudioPlayer? _player;
  String _systemText = '';
  bool _finalizing = false;
  void Function(String text)? _onText;
  String? _workspaceId;
  String? _tabId;
  String? _audioPath;
  String? _requestId;
  MobileAiDictationLocation? _requestLocation;
  Future<void>? _activeTranscription;
  bool _cancelRequested = false;
  var _generation = 0;
  int? _activeGeneration;
  Timer? _elapsedTimer;
  DateTime? _recordingStarted;

  @override
  MobileAiDictationState build(String hostId, String targetKey) {
    _lifecycleListener = AppLifecycleListener(onPause: _handleAppPaused);
    ref.onDispose(() {
      _activeGeneration = null;
      _cancelRequested = true;
      _elapsedTimer?.cancel();
      for (final subscription in _subscriptions) {
        unawaited(subscription.cancel());
      }
      unawaited(_speech.cancel());
      final recorder = _recorder;
      if (recorder != null) unawaited(recorder.dispose());
      final player = _player;
      if (player != null) unawaited(player.dispose());
      final activeTranscription = _activeTranscription;
      unawaited(_dispose(activeTranscription));
      _lifecycleListener?.dispose();
    });
    return const MobileAiDictationState();
  }

  void _handleAppPaused() {
    if (state.stage == MobileAiDictationStage.recording) {
      unawaited(cancel());
    }
  }

  bool _isCurrentGeneration(int generation) =>
      _activeGeneration == generation && !_cancelRequested;

  Future<void> _cancelActiveRequest(String requestId) async {
    if (_requestLocation == MobileAiDictationLocation.thisDevice) {
      _whisper.cancel(requestId);
      return;
    }
    try {
      final client = await ref.read(
        hostConnectionControllerProvider(hostId).future,
      );
      await client.cancelMobileAudioTranscription(requestId);
    } on Object {
      // Local cleanup must still complete when the paired device disconnects.
    }
  }

  Future<void> _dispose(Future<void>? activeTranscription) async {
    final requestId = _requestId;
    if (requestId != null) {
      await _cancelActiveRequest(requestId);
    }
    if (activeTranscription != null) {
      try {
        await activeTranscription;
      } on Object {
        // Disposal must release native resources even when transcription fails.
      }
    }
    await _deleteRecording();
  }

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer();
    _player = player;
    _subscriptions.add(
      player.positionStream.listen((position) {
        if (state.stage == MobileAiDictationStage.playing ||
            state.hasRecording) {
          state = state.copyWith(playbackPosition: position);
        }
      }),
    );
    _subscriptions.add(
      player.playerStateStream.listen((playerState) {
        if (playerState.processingState == ProcessingState.completed &&
            state.stage == MobileAiDictationStage.playing) {
          unawaited(player.seek(Duration.zero));
          state = state.copyWith(
            stage: MobileAiDictationStage.recorded,
            playbackPosition: Duration.zero,
          );
        }
      }),
    );
    return player;
  }

  Future<void> start({
    required void Function(String text) onText,
    String? workspaceId,
    String? tabId,
  }) async {
    if (state.stage != MobileAiDictationStage.idle) return;
    final settings = await ref.read(
      mobileAiDictationSettingsControllerProvider.future,
    );
    _validateSettings(settings);
    _systemText = '';
    _finalizing = false;
    _cancelRequested = false;
    final generation = ++_generation;
    _activeGeneration = generation;
    _onText = onText;
    _workspaceId = workspaceId;
    _tabId = tabId;
    try {
      if (settings.location == MobileAiDictationLocation.thisDevice &&
          settings.engine != MobileAiDictationEngine.whisper) {
        await _startSystemRecognition(settings, generation);
      } else {
        await _startRecording(generation);
      }
    } on Object {
      if (_isCurrentGeneration(generation)) {
        await _reset(deleteRecording: true);
      }
      rethrow;
    }
  }

  void _validateSettings(MobileAiDictationSettings settings) {
    if (!settings.enabled) {
      throw StateError('Enable AI Dictation in Settings before recording.');
    }
    if (settings.location == MobileAiDictationLocation.pairedDevice &&
        settings.remoteAudioConsentVersion != _remoteConsentVersion) {
      throw StateError(
        'Allow paired-device audio processing in AI Dictation settings first.',
      );
    }
    if (settings.location == MobileAiDictationLocation.pairedDevice &&
        settings.engine != MobileAiDictationEngine.whisper) {
      throw StateError(
        'Paired-device transcription requires the Whisper engine.',
      );
    }
    if (settings.engine == MobileAiDictationEngine.systemRecognition &&
        settings.systemRecognitionConsentVersion != _onlineConsentVersion) {
      throw StateError(
        'Allow online system recognition in AI Dictation settings first.',
      );
    }
  }

  Future<void> _startSystemRecognition(
    MobileAiDictationSettings settings,
    int generation,
  ) async {
    if (settings.engine == MobileAiDictationEngine.systemOnDevice &&
        !await ref.read(
          mobileAiDictationOnDeviceAvailableProvider(settings.language).future,
        )) {
      throw StateError(
        'On-device speech recognition is unavailable for this device or locale.',
      );
    }
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.speech());
    if (!_isCurrentGeneration(generation)) return;
    _installAudioSessionListeners(session);
    final available = await _speech.initialize(
      onStatus: (status) => _handleSystemStatus(status, generation),
      onError: (error) => _handleSystemError(error, generation),
    );
    if (!available) {
      throw StateError('System speech recognition is unavailable.');
    }
    if (!_isCurrentGeneration(generation)) return;
    await _speech.listen(
      onResult: (result) => _handleSystemResult(result, generation),
      onSoundLevelChange: (level) {
        if (_isCurrentGeneration(generation) &&
            state.stage == MobileAiDictationStage.recording) {
          state = state.copyWith(amplitude: _normalizeSoundLevel(level));
        }
      },
      listenOptions: SpeechListenOptions(
        localeId: settings.language,
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
        onDevice: settings.engine == MobileAiDictationEngine.systemOnDevice,
        autoPunctuation: true,
        listenFor: _maximumRecordingDuration,
      ),
    );
    if (!_isCurrentGeneration(generation)) return;
    _beginElapsedTimer(generation);
    state = const MobileAiDictationState(
      stage: MobileAiDictationStage.recording,
    );
  }

  Future<void> _startRecording(int generation) async {
    final recorder = _recorder ??= AudioRecorder();
    if (!await recorder.hasPermission()) {
      throw StateError('Microphone permission is required for AI Dictation.');
    }
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.speech());
    if (!_isCurrentGeneration(generation)) return;
    _installAudioSessionListeners(session);
    final directory = await getTemporaryDirectory();
    final path = p.join(
      directory.path,
      'alera-mobile-dictation-${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    if (!_isCurrentGeneration(generation)) return;
    await recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        noiseSuppress: true,
      ),
      path: path,
    );
    _audioPath = path;
    _subscriptions.add(
      recorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((
        value,
      ) {
        if (_isCurrentGeneration(generation) &&
            state.stage == MobileAiDictationStage.recording) {
          state = state.copyWith(amplitude: _normalizeDb(value.current));
        }
      }),
    );
    if (!_isCurrentGeneration(generation)) {
      await recorder.cancel();
      return;
    }
    _beginElapsedTimer(generation);
    state = const MobileAiDictationState(
      stage: MobileAiDictationStage.recording,
      audioReviewAvailable: true,
    );
  }

  void _beginElapsedTimer(int generation) {
    _recordingStarted = DateTime.now();
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final started = _recordingStarted;
      if (!_isCurrentGeneration(generation) ||
          started == null ||
          state.stage != MobileAiDictationStage.recording) {
        return;
      }
      final elapsed = DateTime.now().difference(started);
      state = state.copyWith(elapsed: elapsed);
      if (elapsed >= _maximumRecordingDuration) unawaited(stop());
    });
  }

  void _installAudioSessionListeners(AudioSession session) {
    if (_audioSessionListenersInstalled) return;
    _audioSessionListenersInstalled = true;
    _subscriptions.add(
      session.interruptionEventStream.listen((event) {
        if (event.begin && state.stage == MobileAiDictationStage.recording) {
          unawaited(cancel());
        }
      }),
    );
    _subscriptions.add(
      session.becomingNoisyEventStream.listen((_) {
        if (state.stage == MobileAiDictationStage.recording) {
          unawaited(cancel());
        }
      }),
    );
  }

  Future<void> stop() async {
    if (state.stage != MobileAiDictationStage.recording) return;
    _elapsedTimer?.cancel();
    _recordingStarted = null;
    if (_audioPath == null) {
      await _speech.stop();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (_systemText.trim().isEmpty) {
        state = const MobileAiDictationState(
          warning: 'The system recognizer did not produce a transcription.',
        );
        return;
      }
      await _finalize(_systemText, generation: _activeGeneration);
      return;
    }
    final path = await _recorder?.stop() ?? _audioPath;
    if (path == null || !await File(path).exists()) {
      await _reset(deleteRecording: true);
      throw StateError('The microphone did not produce an audio recording.');
    }
    _audioPath = path;
    final playerDuration = await _ensurePlayer().setFilePath(path);
    final duration = playerDuration ?? state.elapsed;
    state = state.copyWith(
      stage: MobileAiDictationStage.recorded,
      duration: duration,
      elapsed: duration,
      playbackPosition: Duration.zero,
      amplitude: 0,
      audioReviewAvailable: true,
      clearWarning: true,
    );
  }

  Future<void> playPause() async {
    final player = _ensurePlayer();
    if (state.stage == MobileAiDictationStage.playing) {
      await player.pause();
      state = state.copyWith(stage: MobileAiDictationStage.recorded);
      return;
    }
    if (state.stage != MobileAiDictationStage.recorded) return;
    state = state.copyWith(stage: MobileAiDictationStage.playing);
    await player.play();
  }

  Future<void> seek(Duration position) =>
      _player?.seek(position) ?? Future<void>.value();

  Future<void> removeRecording() async => _reset(deleteRecording: true);

  Future<void> cancel() async {
    _elapsedTimer?.cancel();
    _cancelRequested = true;
    try {
      if (_requestId case final requestId?) {
        await _cancelActiveRequest(requestId);
      }
      if (_audioPath == null) {
        await _speech.cancel();
      } else if (state.stage == MobileAiDictationStage.recording) {
        await _recorder?.cancel();
      }
    } finally {
      await _reset(deleteRecording: true);
    }
  }

  Future<void> _reset({required bool deleteRecording, String? warning}) async {
    _elapsedTimer?.cancel();
    _recordingStarted = null;
    _activeGeneration = null;
    _generation++;
    await _player?.stop();
    if (deleteRecording) await _deleteRecording();
    _requestId = null;
    _systemText = '';
    _finalizing = false;
    _onText = null;
    _workspaceId = null;
    _tabId = null;
    state = MobileAiDictationState(warning: warning);
  }

  Future<void> _deleteRecording() async {
    final path = _audioPath;
    _audioPath = null;
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}

double _normalizeDb(double db) => ((db + 60) / 60).clamp(0, 1).toDouble();
double _normalizeSoundLevel(double value) =>
    ((value + 50) / 50).clamp(0, 1).toDouble();
