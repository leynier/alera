// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'package:alera/src/features/ai_dictation/application/ai_dictation_target_registry.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_error.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_provider.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_request.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_result.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_settings.dart';
import 'package:alera/src/features/ai_dictation/infra/ai_dictation_model_store.dart';

class AiDictationService extends ChangeNotifier {
  AiDictationService({
    required AiDictationSettings Function() settings,
    required AiDictationTargetRegistry targets,
    required AiDictationProvider provider,
    this.fallbackProviders = const <AiDictationProvider>[],
    required AiDictationModelStore modelStore,
    AudioRecorder? recorder,
  })  : _settings = settings,
        _targets = targets,
        _provider = provider,
        _modelStore = modelStore,
        _recorder = recorder;

  final AiDictationSettings Function() _settings;
  final AiDictationTargetRegistry _targets;
  final AiDictationProvider _provider;
  final List<AiDictationProvider> fallbackProviders;
  final AiDictationModelStore _modelStore;
  AudioRecorder? _recorder;

  String? _activeTargetId;
  String? _audioPath;
  String? _requestId;
  bool _recording = false;
  bool _transcribing = false;

  bool get isRecording => _recording;
  bool get isTranscribing => _transcribing;
  String? get activeTargetId => _activeTargetId;

  Future<void> start(String targetId) async {
    if (_recording || _transcribing) {
      return;
    }
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
    final localReady = await _modelStore.isInstalled(settings.localModelId);
    final hasFallback =
        settings.hostFallbackEnabled || settings.providerFallbackEnabled;
    if (!localReady && !hasFallback) {
      throw const AiDictationException(
        AiDictationErrorKind.modelUnavailable,
        'Download the Whisper model in Settings before recording.',
      );
    }
    final recorder = _recorder ??= AudioRecorder();
    if (!await recorder.hasPermission()) {
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
    _activeTargetId = targetId;
    _audioPath = path;
    _recording = true;
    notifyListeners();
  }

  Future<AiDictationResult?> stop() async {
    if (!_recording) {
      return null;
    }
    final targetId = _activeTargetId;
    final recorder = _recorder;
    final path = await recorder?.stop() ?? _audioPath;
    _recording = false;
    _transcribing = true;
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
      final localReady = await _modelStore.isInstalled(settings.localModelId);
      final request = AiDictationRequest(
        requestId: requestId,
        audioPath: path,
        modelPath: localReady
            ? await _modelStore.modelPath(settings.localModelId)
            : '',
        language: settings.language,
        initialPrompt: _targets.targetFor(targetId)?.initialPrompt,
        providerModel: settings.remoteModel,
        providerApiKey: Platform.environment['OPENAI_API_KEY'],
        providerBaseUrl: settings.remoteBaseUrl,
        timeout: Duration(seconds: settings.timeoutSeconds),
      );
      final candidates = <AiDictationProvider>[
        if (localReady) _provider,
        if (settings.providerPolicy != AiDictationProviderPolicy.localOnly)
          ...fallbackProviders,
      ];
      AiDictationResult? result;
      AiDictationException? lastError;
      for (final candidate in candidates) {
        if (candidate.id == 'runtime-whisper' &&
            !settings.hostFallbackEnabled) {
          continue;
        }
        if (candidate.id == 'openai-compatible' &&
            !settings.providerFallbackEnabled) {
          continue;
        }
        try {
          result = await candidate.transcribe(request);
          break;
        } on AiDictationException catch (error) {
          lastError = error;
          if (!_canFallback(error.kind)) rethrow;
        }
      }
      if (result == null) {
        throw lastError ??
            const AiDictationException(
              AiDictationErrorKind.transcription,
              'No configured dictation provider is available.',
            );
      }
      if (!_targets.insert(targetId, result.text)) {
        throw const AiDictationException(
          AiDictationErrorKind.targetUnavailable,
          'The text field was closed before dictation finished.',
        );
      }
      return result;
    } finally {
      _resetSession();
      final audioFile = File(path);
      if (await audioFile.exists()) {
        await audioFile.delete();
      }
    }
  }

  bool _canFallback(AiDictationErrorKind kind) =>
      kind == AiDictationErrorKind.modelUnavailable ||
      kind == AiDictationErrorKind.transcription;

  Future<void> cancel() async {
    final path = _audioPath;
    if (_requestId case final requestId?) {
      await _provider.cancel(requestId);
    }
    if (_recording) {
      await _recorder?.stop();
    }
    _resetSession();
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  void _resetSession() {
    _activeTargetId = null;
    _audioPath = null;
    _requestId = null;
    _recording = false;
    _transcribing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_recorder?.dispose() ?? Future<void>.value());
    super.dispose();
  }
}
