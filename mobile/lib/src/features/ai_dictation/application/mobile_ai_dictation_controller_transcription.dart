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
    if (!state.hasRecording || _audioPaths.isEmpty) return;
    final generation = _activeGeneration;
    if (generation == null) return;
    await _player?.pause();
    if (!_isCurrentGeneration(generation)) return;
    final settings = await ref.read(
      mobileAiDictationSettingsControllerProvider.future,
    );
    if (!_isCurrentGeneration(generation)) return;
    _validateSettings(settings);
    state = state.copyWith(
      stage: MobileAiDictationStage.transcribing,
      clearWarning: true,
    );
    final requestId =
        'mobile-dictation-${DateTime.now().microsecondsSinceEpoch}';
    try {
      final assembler = MobileAiDictationTranscriptAssembler();
      if (settings.location == MobileAiDictationLocation.thisDevice) {
        if (settings.engine != MobileAiDictationEngine.whisper) {
          throw StateError(
            'System recognition must record directly on this device.',
          );
        }
        final transfers = ref.read(
          mobileAiDictationModelTransfersProvider.notifier,
        );
        final installed = await transfers.isInstalled(settings.localModelId);
        if (!_isCurrentGeneration(generation)) return;
        if (!installed) {
          throw StateError(
            'Download the selected Whisper model in Settings first.',
          );
        }
        final modelPath = await transfers.modelPath(settings.localModelId);
        if (!_isCurrentGeneration(generation)) return;
        for (var index = 0; index < _audioPaths.length; index++) {
          final segmentRequestId = '$requestId-$index';
          _trackActiveRequest(segmentRequestId, () async {
            _whisper.cancel(segmentRequestId);
          });
          try {
            final result = await _whisper.transcribe(
              requestId: segmentRequestId,
              audioPath: _audioPaths[index],
              modelPath: modelPath,
              language: _whisperLanguage(settings.language),
              initialPrompt: assembler.prompt,
            );
            if (!_isCurrentGeneration(generation)) return;
            assembler.add(result.text);
          } on Object catch (error) {
            if (!_isCurrentGeneration(generation)) return;
            if (!_isSilentSegmentError(error)) rethrow;
          } finally {
            _clearActiveRequest(segmentRequestId);
          }
        }
      } else {
        final client = await ref.read(
          hostConnectionControllerProvider(hostId).future,
        );
        if (!_isCurrentGeneration(generation)) return;
        for (var index = 0; index < _audioPaths.length; index++) {
          final segmentRequestId = '$requestId-$index';
          final audio = await File(_audioPaths[index]).readAsBytes();
          if (!_isCurrentGeneration(generation)) return;
          _trackActiveRequest(
            segmentRequestId,
            () => client.cancelMobileAudioTranscription(segmentRequestId),
          );
          try {
            final response = await client.transcribeMobileAudio(
              requestId: segmentRequestId,
              audio: audio,
              engine: settings.engine.name,
              modelId: settings.remoteModelId,
              language: _whisperLanguage(settings.language),
              initialPrompt: assembler.prompt,
            );
            if (!_isCurrentGeneration(generation)) return;
            final text = response['text']?.toString().trim() ?? '';
            if (text.isNotEmpty) assembler.add(text);
          } on Object catch (error) {
            if (!_isCurrentGeneration(generation)) return;
            if (!_isSilentSegmentError(error)) rethrow;
          } finally {
            _clearActiveRequest(segmentRequestId);
          }
        }
      }
      final text = assembler.text;
      if (text.isEmpty) throw StateError('No speech was detected.');
      if (!_isCurrentGeneration(generation)) return;
      await _finalize(text, generation: generation);
    } on Object catch (error, stackTrace) {
      if (!_isCurrentGeneration(generation)) return;
      _log.warning('mobile dictation transcription failed', error, stackTrace);
      state = state.copyWith(
        stage: MobileAiDictationStage.recorded,
        warning: 'Transcription failed: $error',
      );
    }
  }

  void _handleSystemResult(SpeechRecognitionResult result, int generation) {
    if (!_isCurrentGeneration(generation)) return;
    if (result.finalResult) {
      _appendSystemText(result.recognizedWords);
      _systemLiveText = '';
    } else {
      _systemLiveText = result.recognizedWords;
    }
  }

  void _handleSystemStatus(String status, int generation) {
    if (!_isCurrentGeneration(generation)) return;
    if (status != SpeechToText.doneStatus &&
        status != SpeechToText.notListeningStatus) {
      return;
    }
    if (_systemStopRequested) {
      _appendSystemText(_systemLiveText);
      _systemLiveText = '';
      return;
    }
    _scheduleSystemRestart(generation);
  }

  void _scheduleSystemRestart(int generation) {
    if (_systemRestarting || _systemStopRequested) return;
    _systemRestarting = true;
    unawaited(_restartSystemRecognition(generation));
  }

  Future<void> _restartSystemRecognition(int generation) async {
    try {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final settings = _systemSettings;
      if (settings == null ||
          _systemStopRequested ||
          !_isCurrentGeneration(generation)) {
        return;
      }
      await _listenSystemRecognition(settings, generation);
    } on Object catch (error, stackTrace) {
      _log.warning(
        'mobile speech recognition restart failed',
        error,
        stackTrace,
      );
      if (_isCurrentGeneration(generation)) {
        state = state.copyWith(warning: 'Speech recognition stopped: $error');
      }
    } finally {
      _systemRestarting = false;
    }
  }

  void _appendSystemText(String value) {
    final part = value.trim();
    if (part.isEmpty) return;
    final assembler = MobileAiDictationTranscriptAssembler()..add(_systemText);
    assembler.add(part);
    _systemText = assembler.text;
  }

  void _handleSystemError(SpeechRecognitionError error, int generation) {
    if (!_isCurrentGeneration(generation)) return;
    if (_systemStopRequested) return;
    final message = error.errorMsg.toLowerCase();
    if (message.contains('no match') ||
        message.contains('timeout') ||
        message.contains('timed out')) {
      _scheduleSystemRestart(generation);
      return;
    }
    _log.warning('mobile speech recognition failed: ${error.errorMsg}');
    _elapsedTimer?.cancel();
    _operation.complete();
    state = MobileAiDictationState(
      warning: 'Speech recognition failed: ${error.errorMsg}',
    );
  }

  Future<void> _finalize(String rawText, {int? generation}) async {
    if (!_canContinue(generation) || _finalizing || rawText.trim().isEmpty) {
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
      if (_canContinue(generation)) {
        await _reset(
          deleteRecording: true,
          warning: 'The dictation settings could not be loaded.',
        );
      }
      return;
    }
    if (!_canContinue(generation)) return;
    if (settings.rewriteMode != MobileAiDictationRewriteMode.off) {
      state = state.copyWith(stage: MobileAiDictationStage.improving);
      try {
        final client = await ref.read(
          hostConnectionControllerProvider(hostId).future,
        );
        if (!_canContinue(generation)) return;
        final response = await client.processSpeechMessage(
          operationId: 'mobile-speech-${DateTime.now().microsecondsSinceEpoch}',
          text: output,
          mode: settings.rewriteMode.name,
          workspaceId: _workspaceId,
          tabId: _tabId,
        );
        if (!_canContinue(generation)) return;
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
    if (!_canContinue(generation)) return;
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

bool _isSilentSegmentError(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('did not detect speech') ||
      message.contains('returned no text') ||
      message.contains('no speech was detected');
}
