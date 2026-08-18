// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'mobile_ai_dictation_controller.dart';

extension MobileAiDictationTranscription on MobileAiDictationController {
  Future<void> transcribe() async {
    final operation = _transcribe();
    _activeTranscription = operation;
    try {
      await operation;
    } finally {
      if (identical(_activeTranscription, operation)) {
        _activeTranscription = null;
      }
    }
  }

  Future<void> _transcribe() async {
    if (!state.hasRecording || _audioPath == null) return;
    final generation = _activeGeneration;
    if (generation == null) return;
    await _player?.pause();
    final settings = await ref.read(
      mobileAiDictationSettingsControllerProvider.future,
    );
    _validateSettings(settings);
    if (!_isCurrentGeneration(generation)) return;
    state = state.copyWith(
      stage: MobileAiDictationStage.transcribing,
      clearWarning: true,
    );
    _requestLocation = settings.location;
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
          language: _whisperLanguage(settings.language),
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
          language: _whisperLanguage(settings.language),
        );
        text = response['text']?.toString().trim() ?? '';
        if (text.isEmpty) {
          throw StateError('The paired device returned no text.');
        }
      }
      if (!_isCurrentGeneration(generation)) return;
      await _finalize(text, generation: generation);
    } on Object catch (error, stackTrace) {
      if (_cancelRequested) return;
      _log.warning('mobile dictation transcription failed', error, stackTrace);
      state = state.copyWith(
        stage: MobileAiDictationStage.recorded,
        warning: 'Transcription failed: $error',
      );
    } finally {
      _requestId = null;
      _requestLocation = null;
    }
  }

  void _handleSystemResult(SpeechRecognitionResult result, int generation) {
    if (!_isCurrentGeneration(generation)) return;
    _systemText = result.recognizedWords;
    if (result.finalResult) {
      unawaited(_finalize(_systemText, generation: generation));
    }
  }

  void _handleSystemStatus(String status, int generation) {
    if (!_isCurrentGeneration(generation)) return;
    if ((status == SpeechToText.doneStatus ||
            status == SpeechToText.notListeningStatus) &&
        _systemText.trim().isNotEmpty) {
      unawaited(_finalize(_systemText, generation: generation));
    }
  }

  void _handleSystemError(SpeechRecognitionError error, int generation) {
    if (!_isCurrentGeneration(generation)) return;
    _log.warning('mobile speech recognition failed: ${error.errorMsg}');
    _elapsedTimer?.cancel();
    _activeGeneration = null;
    _generation++;
    state = MobileAiDictationState(
      warning: 'Speech recognition failed: ${error.errorMsg}',
    );
  }

  Future<void> _finalize(String rawText, {int? generation}) async {
    if (_cancelRequested ||
        _finalizing ||
        rawText.trim().isEmpty ||
        generation != null && !_isCurrentGeneration(generation)) {
      return;
    }
    _finalizing = true;
    var output = rawText.trim();
    String? warning;
    late final MobileAiDictationSettings settings;
    try {
      settings = await ref.read(
        mobileAiDictationSettingsControllerProvider.future,
      );
    } on Object catch (error, stackTrace) {
      _log.warning(
        'mobile dictation settings failed during finalization',
        error,
        stackTrace,
      );
      if (!_cancelRequested) {
        await _reset(
          deleteRecording: true,
          warning: 'The dictation settings could not be loaded.',
        );
      }
      return;
    }
    if (_cancelRequested ||
        generation != null && !_isCurrentGeneration(generation)) {
      return;
    }
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
        if (_cancelRequested ||
            generation != null && !_isCurrentGeneration(generation)) {
          return;
        }
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
    if (_cancelRequested ||
        generation != null && !_isCurrentGeneration(generation)) {
      return;
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
}

String? _whisperLanguage(String? language) {
  final value = language?.trim();
  if (value == null || value.isEmpty) return null;
  return value.split(RegExp(r'[-_]')).first.toLowerCase();
}
