// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/ai_dictation/application/ai_dictation_target_registry.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_error.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_provider.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_request.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_result.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_settings.dart';
import 'package:alera/src/features/ai_dictation/infra/ai_dictation_model_store.dart';
import 'package:alera/src/features/ai_dictation/infra/runtime_ai_dictation_speech_processor.dart';
import 'package:alera/src/features/ai_dictation/infra/system_ai_dictation_recognizer.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

enum AiDictationStage { idle, recording, transcribing, improving }

class AiDictationService extends ChangeNotifier {
  AiDictationService({
    required AiDictationSettings Function() settings,
    required AiDictationTargetRegistry targets,
    required AiDictationProvider provider,
    required AiDictationModelStore modelStore,
    required AiDictationSpeechProcessor speechProcessor,
    SystemAiDictationRecognizer? systemRecognizer,
    AudioRecorder? recorder,
  }) : _settings = settings,
       _targets = targets,
       _provider = provider,
       _modelStore = modelStore,
       _speechProcessor = speechProcessor,
       _systemRecognizer = systemRecognizer ?? SystemAiDictationRecognizer(),
       _recorder = recorder;

  final AiDictationSettings Function() _settings;
  final AiDictationTargetRegistry _targets;
  final AiDictationProvider _provider;
  final AiDictationModelStore _modelStore;
  final AiDictationSpeechProcessor _speechProcessor;
  final SystemAiDictationRecognizer _systemRecognizer;
  AudioRecorder? _recorder;

  String? _activeTargetId;
  String? _audioPath;
  String? _requestId;
  String? _processingOperationId;
  String? _lastWarning;
  AiDictationStage _stage = AiDictationStage.idle;
  Future<AiDictationResult?>? _systemFinalization;

  bool get isRecording => _stage == AiDictationStage.recording;
  bool get isTranscribing =>
      _stage == AiDictationStage.transcribing ||
      _stage == AiDictationStage.improving;
  bool get isImproving => _stage == AiDictationStage.improving;
  AiDictationStage get stage => _stage;
  String? get activeTargetId => _activeTargetId;

  String? takeWarning() {
    final warning = _lastWarning;
    _lastWarning = null;
    return warning;
  }

  Future<void> start(String targetId) async {
    if (_stage != AiDictationStage.idle) return;
    final settings = _settings();
    if (!settings.enabled) {
      throw const AiDictationException(
        AiDictationErrorKind.disabled,
        'Enable AI Dictation in Settings before recording.',
      );
    }
    final target = _targets.targetFor(targetId);
    if (target == null) {
      throw const AiDictationException(
        AiDictationErrorKind.targetUnavailable,
        'The dictation text field is no longer available.',
      );
    }
    _lastWarning = null;
    _activeTargetId = targetId;
    if (settings.transcriptionEngine !=
        AiDictationTranscriptionEngine.localWhisper) {
      await _startSystemRecognition(settings, targetId);
      return;
    }
    if (!await _modelStore.isInstalled(settings.localModelId)) {
      _activeTargetId = null;
      throw const AiDictationException(
        AiDictationErrorKind.modelUnavailable,
        'Download the selected Whisper model in Settings before recording.',
      );
    }
    final recorder = _recorder ??= AudioRecorder();
    if (!await recorder.hasPermission()) {
      _activeTargetId = null;
      throw const AiDictationException(
        AiDictationErrorKind.permissionDenied,
        'Microphone permission is required for AI Dictation.',
      );
    }
    final directory = await getTemporaryDirectory();
    final path = p.join(
      directory.path,
      'alera-dictation-${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    await recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
    _audioPath = path;
    _stage = AiDictationStage.recording;
    notifyListeners();
  }

  Future<void> _startSystemRecognition(
    AiDictationSettings settings,
    String targetId,
  ) async {
    if (settings.transcriptionEngine ==
            AiDictationTranscriptionEngine.systemOnDevice &&
        !await SystemAiDictationRecognizer.supportsOnDevice(
          settings.language,
        )) {
      _activeTargetId = null;
      throw const AiDictationException(
        AiDictationErrorKind.transcription,
        'On-device speech recognition is unavailable for this locale.',
      );
    }
    if (settings.transcriptionEngine ==
            AiDictationTranscriptionEngine.systemRecognition &&
        settings.systemRecognitionConsentVersion != 1) {
      _activeTargetId = null;
      throw const AiDictationException(
        AiDictationErrorKind.permissionDenied,
        'Allow online speech recognition in AI Dictation settings first.',
      );
    }
    try {
      await _systemRecognizer.start(
        localeId: settings.language,
        onDevice:
            settings.transcriptionEngine ==
            AiDictationTranscriptionEngine.systemOnDevice,
        onFinal: (text) => unawaited(_finalizeSystem(targetId, text)),
        onError: (error) {
          _lastWarning = 'System speech recognition failed: $error';
          if (_systemFinalization == null) _resetSession();
        },
      );
    } on Object catch (error) {
      _activeTargetId = null;
      throw AiDictationException(
        AiDictationErrorKind.transcription,
        'System speech recognition could not start: $error',
        cause: error,
      );
    }
    _stage = AiDictationStage.recording;
    notifyListeners();
  }

  Future<AiDictationResult?> stop() async {
    if (_stage != AiDictationStage.recording) return _systemFinalization;
    final targetId = _activeTargetId;
    if (_audioPath == null) {
      final text = await _systemRecognizer.stop();
      if (targetId == null || text.trim().isEmpty) {
        _resetSession();
        throw const AiDictationException(
          AiDictationErrorKind.audio,
          'The system recognizer did not produce a transcription.',
        );
      }
      return _finalizeSystem(targetId, text);
    }
    return _stopWhisper(targetId);
  }

  Future<AiDictationResult?> _stopWhisper(String? targetId) async {
    final recorder = _recorder;
    final path = await recorder?.stop() ?? _audioPath;
    _stage = AiDictationStage.transcribing;
    notifyListeners();
    if (path == null || targetId == null) {
      _resetSession();
      throw const AiDictationException(
        AiDictationErrorKind.audio,
        'The microphone did not produce an audio recording.',
      );
    }
    final requestId = 'dictation-${DateTime.now().microsecondsSinceEpoch}';
    _requestId = requestId;
    try {
      final settings = _settings();
      final result = await _provider.transcribe(
        AiDictationRequest(
          requestId: requestId,
          audioPath: path,
          modelPath: await _modelStore.modelPath(settings.localModelId),
          language: settings.language,
          initialPrompt: _targets.targetFor(targetId)?.initialPrompt,
          timeout: Duration(seconds: settings.timeoutSeconds),
        ),
      );
      return _finishTranscript(targetId, result);
    } finally {
      final audioFile = File(path);
      if (await audioFile.exists()) await audioFile.delete();
    }
  }

  Future<AiDictationResult?> _finalizeSystem(String targetId, String text) {
    final active = _systemFinalization;
    if (active != null) return active;
    final started = DateTime.now();
    _stage = AiDictationStage.transcribing;
    notifyListeners();
    final future = _finishTranscript(
      targetId,
      AiDictationResult(
        text: text,
        providerId: 'system-speech-recognition',
        elapsed: DateTime.now().difference(started),
        duration: Duration.zero,
      ),
    );
    _systemFinalization = future;
    return future;
  }

  Future<AiDictationResult?> _finishTranscript(
    String targetId,
    AiDictationResult rawResult,
  ) async {
    try {
      var text = rawResult.text.trim();
      final settings = _settings();
      final target = _targets.targetFor(targetId);
      if (target == null) {
        throw const AiDictationException(
          AiDictationErrorKind.targetUnavailable,
          'The text field was closed before dictation finished.',
        );
      }
      if (settings.rewriteMode != AiDictationRewriteMode.off) {
        _stage = AiDictationStage.improving;
        notifyListeners();
        final operationId =
            'speech-message-${DateTime.now().microsecondsSinceEpoch}';
        _processingOperationId = operationId;
        try {
          final processed = await _speechProcessor.process(
            operationId: operationId,
            text: text,
            mode: settings.rewriteMode,
            target: target,
          );
          text = processed.text;
        } on Object catch (error) {
          _lastWarning =
              'The transcript was inserted without speech processing: $error';
        }
      }
      if (!_targets.insert(targetId, text)) {
        throw const AiDictationException(
          AiDictationErrorKind.targetUnavailable,
          'The text field was closed before dictation finished.',
        );
      }
      return AiDictationResult(
        text: text,
        providerId: rawResult.providerId,
        elapsed: rawResult.elapsed,
        duration: rawResult.duration,
        detectedLanguage: rawResult.detectedLanguage,
      );
    } finally {
      _resetSession();
    }
  }

  Future<void> cancel() async {
    final path = _audioPath;
    if (_processingOperationId case final operationId?) {
      await _speechProcessor.cancel(operationId);
    }
    if (_requestId case final requestId?) await _provider.cancel(requestId);
    if (_audioPath == null) {
      await _systemRecognizer.cancel();
    } else if (_stage == AiDictationStage.recording) {
      await _recorder?.stop();
    }
    _resetSession();
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  void _resetSession() {
    _activeTargetId = null;
    _audioPath = null;
    _requestId = null;
    _processingOperationId = null;
    _systemFinalization = null;
    _stage = AiDictationStage.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_recorder?.dispose() ?? Future<void>.value());
    super.dispose();
  }
}
