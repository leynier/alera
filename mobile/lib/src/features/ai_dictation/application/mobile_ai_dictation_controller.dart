import 'dart:async';

import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/ai_dictation/domain/mobile_ai_dictation_settings.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

part 'mobile_ai_dictation_controller.g.dart';

const _capabilityChannel = MethodChannel(
  'dev.leynier.alera/speech_capabilities',
);
const _onlineConsentVersion = 1;

enum MobileAiDictationStage { idle, listening, processing }

class MobileAiDictationState {
  const MobileAiDictationState({
    this.stage = MobileAiDictationStage.idle,
    this.warning,
  });

  final MobileAiDictationStage stage;
  final String? warning;
}

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
  final _log = Logger('MobileAiDictationController');
  String _text = '';
  bool _finalizing = false;
  void Function(String text)? _onText;
  String? _workspaceId;
  String? _tabId;

  @override
  MobileAiDictationState build(String hostId, String targetKey) {
    ref.onDispose(() => unawaited(_speech.cancel()));
    return const MobileAiDictationState();
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
    if (!settings.enabled) {
      throw StateError('Enable AI Dictation in Settings before recording.');
    }
    if (settings.engine == MobileAiDictationEngine.systemRecognition &&
        settings.systemRecognitionConsentVersion != _onlineConsentVersion) {
      throw StateError(
        'Allow online system recognition in AI Dictation settings first.',
      );
    }
    if (settings.engine == MobileAiDictationEngine.systemOnDevice &&
        !await ref.read(
          mobileAiDictationOnDeviceAvailableProvider(settings.language).future,
        )) {
      throw StateError(
        'On-device speech recognition is unavailable for this device or locale.',
      );
    }
    _text = '';
    _finalizing = false;
    _onText = onText;
    _workspaceId = workspaceId;
    _tabId = tabId;
    final available = await _speech.initialize(
      onStatus: _handleStatus,
      onError: _handleError,
    );
    if (!available) {
      throw StateError('System speech recognition is unavailable.');
    }
    await _speech.listen(
      onResult: _handleResult,
      listenOptions: SpeechListenOptions(
        localeId: settings.language,
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
        onDevice: settings.engine == MobileAiDictationEngine.systemOnDevice,
        autoPunctuation: true,
      ),
    );
    state = const MobileAiDictationState(
      stage: MobileAiDictationStage.listening,
    );
  }

  Future<void> stop() async {
    if (state.stage != MobileAiDictationStage.listening) return;
    await _speech.stop();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (_text.trim().isEmpty) {
      state = const MobileAiDictationState(
        warning: 'The system recognizer did not produce a transcription.',
      );
      return;
    }
    await _finalize(_text);
  }

  Future<void> cancel() async {
    await _speech.cancel();
    state = const MobileAiDictationState();
  }

  void _handleResult(SpeechRecognitionResult result) {
    _text = result.recognizedWords;
    if (result.finalResult) unawaited(_finalize(_text));
  }

  void _handleStatus(String status) {
    if ((status == SpeechToText.doneStatus ||
            status == SpeechToText.notListeningStatus) &&
        _text.trim().isNotEmpty) {
      unawaited(_finalize(_text));
    }
  }

  void _handleError(SpeechRecognitionError error) {
    _log.warning('mobile speech recognition failed: ${error.errorMsg}');
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
      state = const MobileAiDictationState(
        stage: MobileAiDictationStage.processing,
      );
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
    state = MobileAiDictationState(warning: warning);
  }
}
