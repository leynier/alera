import 'dart:typed_data';

import 'speech_model_descriptor.dart';

class const SpeechPartialResult({
  required final String text,
  final bool isFinal = false,
});

class const SpeechFinalResult({
  required final String text,
  final String? detectedLanguage,
  final SpeechExecutionProvider executionProvider = SpeechExecutionProvider.cpu,
});

class const SpeechTranscriptionRequest({
  required final String requestId,
  required final String audioPath,
  final String? language,
  final String? initialPrompt,
});

abstract interface class StreamingSpeechSession {
  Stream<SpeechPartialResult> get partialResults;

  Future<void> acceptPcm16(
    Uint8List bytes, {
    required int sampleRate,
    required int channels,
  });

  Future<SpeechFinalResult> finish();

  Future<void> cancel();

  Future<void> dispose();
}

abstract interface class BatchSpeechTranscriber {
  Future<SpeechFinalResult> transcribe(SpeechTranscriptionRequest request);

  Future<void> cancel(String requestId);
}
