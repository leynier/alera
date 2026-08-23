import 'dart:typed_data';

import 'speech_model_descriptor.dart';

class SpeechPartialResult {
  const SpeechPartialResult({required this.text, this.isFinal = false});

  final String text;
  final bool isFinal;
}

class SpeechFinalResult {
  const SpeechFinalResult({
    required this.text,
    this.detectedLanguage,
    this.executionProvider = SpeechExecutionProvider.cpu,
  });

  final String text;
  final String? detectedLanguage;
  final SpeechExecutionProvider executionProvider;
}

class SpeechTranscriptionRequest {
  const SpeechTranscriptionRequest({
    required this.requestId,
    required this.audioPath,
    this.language,
    this.initialPrompt,
  });

  final String requestId;
  final String audioPath;
  final String? language;
  final String? initialPrompt;
}

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
