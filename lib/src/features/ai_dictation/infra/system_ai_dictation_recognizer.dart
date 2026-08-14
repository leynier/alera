import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

part 'system_ai_dictation_recognizer.g.dart';

const _capabilityChannel = MethodChannel(
  'dev.leynier.alera/speech_capabilities',
);

@riverpod
Future<bool> aiDictationOnDeviceAvailable(Ref ref, String? localeId) async {
  return SystemAiDictationRecognizer.supportsOnDevice(localeId);
}

class SystemAiDictationRecognizer {
  SystemAiDictationRecognizer({SpeechToText? speech})
    : _speech = speech ?? SpeechToText();

  static Future<bool> supportsOnDevice(String? localeId) async {
    if (!Platform.isMacOS) return false;
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

  final SpeechToText _speech;
  String _text = '';
  bool _finalDelivered = false;
  void Function(String text)? _onFinal;
  void Function(Object error)? _onError;

  Future<void> start({
    required String? localeId,
    required bool onDevice,
    required void Function(String text) onFinal,
    required void Function(Object error) onError,
  }) async {
    _text = '';
    _finalDelivered = false;
    _onFinal = onFinal;
    _onError = onError;
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
        localeId: localeId,
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
        onDevice: onDevice,
        autoPunctuation: true,
      ),
    );
  }

  Future<String> stop() async {
    await _speech.stop();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return _text.trim();
  }

  Future<void> cancel() => _speech.cancel();

  void _handleResult(SpeechRecognitionResult result) {
    _text = result.recognizedWords;
    if (result.finalResult) _deliverFinal();
  }

  void _handleStatus(String status) {
    if (status == SpeechToText.doneStatus ||
        status == SpeechToText.notListeningStatus) {
      _deliverFinal();
    }
  }

  void _handleError(SpeechRecognitionError error) {
    _onError?.call(StateError(error.errorMsg));
  }

  void _deliverFinal() {
    if (_finalDelivered || _text.trim().isEmpty) return;
    _finalDelivered = true;
    _onFinal?.call(_text.trim());
  }
}
