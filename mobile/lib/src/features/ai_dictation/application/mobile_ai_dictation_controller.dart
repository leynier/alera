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
  AudioRecorder? _recorder;
  AudioPlayer? _player;
  String _systemText = '';
  bool _finalizing = false;
  void Function(String text)? _onText;
  String? _workspaceId;
  String? _tabId;
  String? _audioPath;
  String? _requestId;
  Timer? _elapsedTimer;
  DateTime? _recordingStarted;

  @override
  MobileAiDictationState build(String hostId, String targetKey) {
    ref.onDispose(() {
      _elapsedTimer?.cancel();
      for (final subscription in _subscriptions) {
        unawaited(subscription.cancel());
      }
      unawaited(_speech.cancel());
      final recorder = _recorder;
      if (recorder != null) unawaited(recorder.dispose());
      final player = _player;
      if (player != null) unawaited(player.dispose());
      unawaited(_deleteRecording());
    });
    return const MobileAiDictationState();
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
    _onText = onText;
    _workspaceId = workspaceId;
    _tabId = tabId;
    if (settings.location == MobileAiDictationLocation.thisDevice &&
        settings.engine != MobileAiDictationEngine.whisper) {
      await _startSystemRecognition(settings);
    } else {
      await _startRecording();
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
    if (settings.engine == MobileAiDictationEngine.systemRecognition &&
        settings.systemRecognitionConsentVersion != _onlineConsentVersion) {
      throw StateError(
        'Allow online system recognition in AI Dictation settings first.',
      );
    }
  }

  Future<void> _startSystemRecognition(
    MobileAiDictationSettings settings,
  ) async {
    if (settings.engine == MobileAiDictationEngine.systemOnDevice &&
        !await ref.read(
          mobileAiDictationOnDeviceAvailableProvider(settings.language).future,
        )) {
      throw StateError(
        'On-device speech recognition is unavailable for this device or locale.',
      );
    }
    final available = await _speech.initialize(
      onStatus: _handleSystemStatus,
      onError: _handleSystemError,
    );
    if (!available) {
      throw StateError('System speech recognition is unavailable.');
    }
    await _speech.listen(
      onResult: _handleSystemResult,
      onSoundLevelChange: (level) {
        if (state.stage == MobileAiDictationStage.recording) {
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
    _beginElapsedTimer();
    state = const MobileAiDictationState(
      stage: MobileAiDictationStage.recording,
    );
  }

  Future<void> _startRecording() async {
    final recorder = _recorder ??= AudioRecorder();
    if (!await recorder.hasPermission()) {
      throw StateError('Microphone permission is required for AI Dictation.');
    }
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.speech());
    final directory = await getTemporaryDirectory();
    final path = p.join(
      directory.path,
      'alera-mobile-dictation-${DateTime.now().microsecondsSinceEpoch}.wav',
    );
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
        if (state.stage == MobileAiDictationStage.recording) {
          state = state.copyWith(amplitude: _normalizeDb(value.current));
        }
      }),
    );
    _beginElapsedTimer();
    state = const MobileAiDictationState(
      stage: MobileAiDictationStage.recording,
      audioReviewAvailable: true,
    );
  }

  void _beginElapsedTimer() {
    _recordingStarted = DateTime.now();
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final started = _recordingStarted;
      if (started == null || state.stage != MobileAiDictationStage.recording) {
        return;
      }
      final elapsed = DateTime.now().difference(started);
      state = state.copyWith(elapsed: elapsed);
      if (elapsed >= _maximumRecordingDuration) unawaited(stop());
    });
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
      await _finalize(_systemText);
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

  Future<void> transcribe() async {
    if (!state.hasRecording || _audioPath == null) return;
    await _player?.pause();
    final settings = await ref.read(
      mobileAiDictationSettingsControllerProvider.future,
    );
    _validateSettings(settings);
    state = state.copyWith(
      stage: MobileAiDictationStage.transcribing,
      clearWarning: true,
    );
    final requestId =
        'mobile-dictation-${DateTime.now().microsecondsSinceEpoch}';
    _requestId = requestId;
    try {
      final String text;
      if (settings.location == MobileAiDictationLocation.thisDevice) {
        if (settings.engine != MobileAiDictationEngine.whisper) {
          throw StateError(
            'System recognition must record directly on this device.',
          );
        }
        final transfers = ref.read(
          mobileAiDictationModelTransfersProvider.notifier,
        );
        if (!await transfers.isInstalled(settings.localModelId)) {
          throw StateError(
            'Download the selected Whisper model in Settings first.',
          );
        }
        final result = await _whisper.transcribe(
          requestId: requestId,
          audioPath: _audioPath!,
          modelPath: await transfers.modelPath(settings.localModelId),
          language: settings.language,
        );
        text = result.text;
      } else {
        final client = await ref.read(
          hostConnectionControllerProvider(hostId).future,
        );
        final response = await client.transcribeMobileAudio(
          requestId: requestId,
          audio: await File(_audioPath!).readAsBytes(),
          engine: settings.engine.name,
          modelId: settings.remoteModelId,
          language: settings.language,
        );
        text = response['text']?.toString().trim() ?? '';
        if (text.isEmpty) {
          throw StateError('The paired device returned no text.');
        }
      }
      await _finalize(text);
    } on Object catch (error, stackTrace) {
      _log.warning('mobile dictation transcription failed', error, stackTrace);
      state = state.copyWith(
        stage: MobileAiDictationStage.recorded,
        warning: 'Transcription failed: $error',
      );
    } finally {
      _requestId = null;
    }
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
    if (_requestId case final requestId?) {
      final settings = await ref.read(
        mobileAiDictationSettingsControllerProvider.future,
      );
      if (settings.location == MobileAiDictationLocation.thisDevice) {
        _whisper.cancel(requestId);
      } else {
        try {
          final client = await ref.read(
            hostConnectionControllerProvider(hostId).future,
          );
          await client.cancelMobileAudioTranscription(requestId);
        } on Object {
          // Local cleanup must still complete when the paired device disconnects.
        }
      }
    }
    if (_audioPath == null) {
      await _speech.cancel();
    } else if (state.stage == MobileAiDictationStage.recording) {
      await _recorder?.cancel();
    }
    await _reset(deleteRecording: true);
  }

  void _handleSystemResult(SpeechRecognitionResult result) {
    _systemText = result.recognizedWords;
    if (result.finalResult) unawaited(_finalize(_systemText));
  }

  void _handleSystemStatus(String status) {
    if ((status == SpeechToText.doneStatus ||
            status == SpeechToText.notListeningStatus) &&
        _systemText.trim().isNotEmpty) {
      unawaited(_finalize(_systemText));
    }
  }

  void _handleSystemError(SpeechRecognitionError error) {
    _log.warning('mobile speech recognition failed: ${error.errorMsg}');
    _elapsedTimer?.cancel();
    state = MobileAiDictationState(
      warning: 'Speech recognition failed: ${error.errorMsg}',
    );
  }

  Future<void> _finalize(String rawText) async {
    if (_finalizing || rawText.trim().isEmpty) return;
    _finalizing = true;
    var output = rawText.trim();
    String? warning;
    final settings = await ref.read(
      mobileAiDictationSettingsControllerProvider.future,
    );
    if (settings.rewriteMode != MobileAiDictationRewriteMode.off) {
      state = state.copyWith(stage: MobileAiDictationStage.improving);
      try {
        final client = await ref.read(
          hostConnectionControllerProvider(hostId).future,
        );
        final response = await client.processSpeechMessage(
          operationId: 'mobile-speech-${DateTime.now().microsecondsSinceEpoch}',
          text: output,
          mode: settings.rewriteMode.name,
          workspaceId: _workspaceId,
          tabId: _tabId,
        );
        final processed = response['text']?.toString().trim() ?? '';
        if (processed.isEmpty) {
          throw StateError('The speech processing agent returned no text.');
        }
        output = processed;
      } on Object catch (error, stackTrace) {
        _log.warning('mobile speech processing failed', error, stackTrace);
        warning =
            'The raw transcript was used because speech processing failed.';
      }
    }
    try {
      _onText?.call(output);
    } on Object catch (error, stackTrace) {
      _log.warning(
        'mobile dictation target was unavailable',
        error,
        stackTrace,
      );
      warning = 'The dictation field was closed before transcription finished.';
    }
    await _reset(deleteRecording: true, warning: warning);
  }

  Future<void> _reset({required bool deleteRecording, String? warning}) async {
    _elapsedTimer?.cancel();
    _recordingStarted = null;
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
