import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:alera_mobile/src/features/ai_dictation/infra/mobile_ai_dictation_model_store.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';

/// Captures a phone recording and exposes the host/provider fallback entry
/// point used by mobile composers. The local model path is deliberately kept
/// on the phone and is never included in a runtime upload.
class MobileAiDictationService {
  MobileAiDictationService(
      {required this.runtime,
      AudioRecorder? recorder,
      MobileAiDictationModelStore? models})
      : _recorder = recorder ?? AudioRecorder(),
        _models = models ?? MobileAiDictationModelStore();

  final MobileRuntimeClient runtime;
  final AudioRecorder _recorder;
  final MobileAiDictationModelStore _models;
  String? _path;

  Future<String> localModelPath() => _models.path();

  Future<void> start() async {
    if (!await _recorder.hasPermission())
      throw const AudioRecorderException('Microphone permission is required.');
    final directory = await getTemporaryDirectory();
    _path =
        '${directory.path}${Platform.pathSeparator}alera-mobile-dictation-${DateTime.now().microsecondsSinceEpoch}.wav';
    await _recorder.start(
        const RecordConfig(
            encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
        path: _path!);
  }

  Future<Map<String, Object?>> stop(
      {String? language, String? initialPrompt}) async {
    final path = await _recorder.stop() ?? _path;
    if (path == null)
      throw StateError('The microphone did not produce a recording.');
    try {
      final bytes = await File(path).readAsBytes();
      return runtime.transcribeMobileAudio(
          audio: bytes, language: language, initialPrompt: initialPrompt);
    } finally {
      final file = File(path);
      if (await file.exists()) await file.delete();
      _path = null;
    }
  }

  Future<void> dispose() async {
    await _recorder.dispose();
    _models.dispose();
  }
}

class AudioRecorderException implements Exception {
  const AudioRecorderException(this.message);
  final String message;
  @override
  String toString() => message;
}
