import 'dart:async';
import 'dart:io';

import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_model_transfers.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_provider_credentials.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_state.dart';
import 'package:alera_mobile/src/features/ai_dictation/domain/mobile_ai_dictation_operation.dart';
import 'package:alera_mobile/src/features/ai_dictation/domain/mobile_ai_dictation_settings.dart';
import 'package:alera_mobile/src/features/ai_dictation/domain/mobile_ai_dictation_transcript_assembler.dart';
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
part 'mobile_ai_dictation_controller_lifecycle.dart';
part 'mobile_ai_dictation_controller_recording.dart';
part 'mobile_ai_dictation_controller_transcription.dart';

const _capabilityChannel = MethodChannel(
  'dev.leynier.alera/speech_capabilities',
);
const _onlineConsentVersion = 1;
const _remoteConsentVersion = 1;
const _recordingSegmentDuration = Duration(seconds: 30);

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
  String _systemLiveText = '';
  MobileAiDictationSettings? _systemSettings;
  bool _systemStopRequested = false;
  bool _systemRestarting = false;
  bool _finalizing = false;
  void Function(String text)? _onText;
  String? _workspaceId;
  String? _tabId;
  String? _audioPath;
  final _audioPaths = <String>[];
  Timer? _segmentTimer;
  Future<void>? _segmentRotation;
  Future<void>? _activeTranscription;
  final _operation = MobileAiDictationOperation();
  ({String id, Future<void> Function() cancel})? _activeRequest;
  Timer? _elapsedTimer;
  DateTime? _recordingStarted;

  @override
  MobileAiDictationState build(String hostId, String targetKey) {
    _lifecycleListener = AppLifecycleListener(onPause: _handleAppPaused);
    ref.onDispose(() {
      _operation.dispose();
      _elapsedTimer?.cancel();
      _segmentTimer?.cancel();
      for (final subscription in _subscriptions) {
        unawaited(subscription.cancel());
      }
      unawaited(_speech.cancel());
      final recorder = _recorder;
      if (recorder != null) unawaited(recorder.dispose());
      final player = _player;
      if (player != null) unawaited(player.dispose());
      final activeTranscription = _activeTranscription;
      final activeRequest = _activeRequest;
      _activeRequest = null;
      unawaited(_dispose(activeTranscription, activeRequest));
      _lifecycleListener?.dispose();
    });
    return const MobileAiDictationState();
  }

  Future<void> start({
    required void Function(String text) onText,
    String? workspaceId,
    String? tabId,
  }) async {
    if (state.stage != MobileAiDictationStage.idle) return;
    final generation = _operation.begin();
    _onText = onText;
    _workspaceId = workspaceId;
    _tabId = tabId;
    try {
      final settings = await ref.read(
        mobileAiDictationSettingsControllerProvider.future,
      );
      if (!_isCurrentGeneration(generation)) return;
      _validateSettings(settings);
      _systemText = '';
      _systemLiveText = '';
      _systemSettings = settings;
      _systemStopRequested = false;
      _finalizing = false;
      if (settings.location == MobileAiDictationLocation.thisDevice &&
          (settings.engine == MobileAiDictationEngine.systemOnDevice ||
              settings.engine == MobileAiDictationEngine.systemRecognition)) {
        await _startSystemRecognition(settings, generation);
      } else {
        await _startRecording(generation);
      }
    } on Object {
      if (!_isCurrentGeneration(generation)) return;
      await _reset(deleteRecording: true);
      rethrow;
    }
  }

  void _validateSettings(MobileAiDictationSettings settings) {
    if (!settings.enabled) {
      throw StateError('Enable AI Dictation in Settings before recording.');
    }
    if (settings.requiresRemoteAudioConsent &&
        settings.remoteAudioConsentVersion != _remoteConsentVersion) {
      throw StateError(
        'Allow remote audio processing in AI Dictation settings first.',
      );
    }
    if (settings.location == MobileAiDictationLocation.pairedDevice &&
        (settings.engine == MobileAiDictationEngine.systemOnDevice ||
            settings.engine == MobileAiDictationEngine.systemRecognition)) {
      throw StateError(
        'The selected system recognition engine only runs on this device.',
      );
    }
    if (settings.location == MobileAiDictationLocation.thisDevice &&
        settings.engine == MobileAiDictationEngine.codexSubscription) {
      throw StateError(
        'Codex subscription dictation requires a paired runtime.',
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
    if (settings.engine == MobileAiDictationEngine.systemOnDevice) {
      final available = await ref.read(
        mobileAiDictationOnDeviceAvailableProvider(settings.language).future,
      );
      if (!_isCurrentGeneration(generation)) return;
      if (!available) {
        throw StateError(
          'On-device speech recognition is unavailable for this device or locale.',
        );
      }
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
    await _listenSystemRecognition(settings, generation);
    if (!_isCurrentGeneration(generation)) return;
    _beginElapsedTimer(generation);
    state = const MobileAiDictationState(
      stage: MobileAiDictationStage.recording,
    );
  }

  Future<void> _listenSystemRecognition(
    MobileAiDictationSettings settings,
    int generation,
  ) async {
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
      ),
    );
  }

  Future<void> _startRecording(int generation) async {
    final recorder = _recorder ??= AudioRecorder();
    final hasPermission = await recorder.hasPermission();
    if (!_isCurrentGeneration(generation)) return;
    if (!hasPermission) {
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
    if (!_isCurrentGeneration(generation)) {
      await recorder.cancel();
      return;
    }
    _audioPath = path;
    _audioPaths.add(path);
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
    _beginElapsedTimer(generation);
    _segmentTimer = Timer.periodic(_recordingSegmentDuration, (_) {
      _segmentRotation ??= _rotateRecordingSegment(generation).whenComplete(() {
        _segmentRotation = null;
      });
    });
    state = const MobileAiDictationState(
      stage: MobileAiDictationStage.recording,
      audioReviewAvailable: true,
    ).copyWith(segmentCount: _audioPaths.length);
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
    });
  }

  void _installAudioSessionListeners(AudioSession session) {
    if (_audioSessionListenersInstalled) return;
    _audioSessionListenersInstalled = true;
    _subscriptions.add(
      session.interruptionEventStream.listen((event) {
        if (ref.mounted &&
            event.begin &&
            state.stage == MobileAiDictationStage.recording) {
          unawaited(cancel());
        }
      }),
    );
    _subscriptions.add(
      session.becomingNoisyEventStream.listen((_) {
        if (ref.mounted && state.stage == MobileAiDictationStage.recording) {
          unawaited(cancel());
        }
      }),
    );
  }

  Future<void> stop() async {
    if (state.stage != MobileAiDictationStage.recording) return;
    final generation = _activeGeneration;
    if (generation == null) return;
    _elapsedTimer?.cancel();
    _segmentTimer?.cancel();
    _recordingStarted = null;
    if (_audioPaths.isEmpty) {
      _systemStopRequested = true;
      await _speech.stop();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!_isCurrentGeneration(generation)) return;
      if (_systemText.trim().isEmpty) {
        state = const MobileAiDictationState(
          warning: 'The system recognizer did not produce a transcription.',
        );
        return;
      }
      await _finalize(_systemText, generation: generation);
      return;
    }
    final rotation = _segmentRotation;
    if (rotation != null) await rotation;
    if (!_isCurrentGeneration(generation)) return;
    final path = await _recorder?.stop() ?? _audioPath;
    if (!_isCurrentGeneration(generation)) return;
    if (path != null && _audioPaths.isNotEmpty && path != _audioPaths.last) {
      _audioPaths[_audioPaths.length - 1] = path;
      _audioPath = path;
    }
    final filesExist =
        _audioPaths.isNotEmpty &&
        (await Future.wait(
          _audioPaths.map((value) => File(value).exists()),
        )).every((value) => value);
    if (!_isCurrentGeneration(generation)) return;
    if (!filesExist) {
      await _reset(deleteRecording: true);
      throw StateError('The microphone did not produce an audio recording.');
    }
    final playerDuration = await _ensurePlayer().setAudioSources(
      _audioPaths.map(AudioSource.file).toList(),
    );
    if (!_isCurrentGeneration(generation)) return;
    final duration = playerDuration ?? state.elapsed;
    state = state.copyWith(
      stage: MobileAiDictationStage.recorded,
      duration: duration,
      elapsed: duration,
      playbackPosition: Duration.zero,
      amplitude: 0,
      audioReviewAvailable: true,
      segmentCount: _audioPaths.length,
      clearWarning: true,
    );
  }

  Future<void> playPause() async {
    final player = _ensurePlayer();
    final generation = _activeGeneration;
    if (generation == null) return;
    if (state.stage == MobileAiDictationStage.playing) {
      await player.pause();
      if (!_isCurrentGeneration(generation)) return;
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
    final wasRecording =
        ref.mounted && state.stage == MobileAiDictationStage.recording;
    _elapsedTimer?.cancel();
    _operation.cancel();
    try {
      if (_activeRequest case final activeRequest?) {
        await _cancelActiveRequest(activeRequest);
      }
      if (_audioPaths.isEmpty) {
        await _speech.cancel();
      } else if (wasRecording) {
        final rotation = _segmentRotation;
        if (rotation != null) {
          try {
            await rotation;
          } on Object catch (error, stackTrace) {
            _log.warning(
              'dictation segment rotation failed during cancel',
              error,
              stackTrace,
            );
          }
        }
        await _recorder?.cancel();
      }
    } finally {
      await _reset(deleteRecording: true);
    }
  }

  Future<void> _reset({required bool deleteRecording, String? warning}) async {
    _elapsedTimer?.cancel();
    _segmentTimer?.cancel();
    _recordingStarted = null;
    _operation.complete();
    await _player?.stop();
    if (deleteRecording) await _deleteRecording();
    _systemText = '';
    _systemLiveText = '';
    _systemSettings = null;
    _systemStopRequested = false;
    _systemRestarting = false;
    _finalizing = false;
    _onText = null;
    _workspaceId = null;
    _tabId = null;
    if (!ref.mounted) return;
    state = MobileAiDictationState(warning: warning);
  }

  int? get _activeGeneration => _operation.activeGeneration;
}

double _normalizeDb(double db) => ((db + 60) / 60).clamp(0, 1).toDouble();
double _normalizeSoundLevel(double value) =>
    ((value + 50) / 50).clamp(0, 1).toDouble();
