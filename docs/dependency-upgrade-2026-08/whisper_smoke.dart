import 'dart:convert';
import 'dart:io';

import 'package:alera/src/rust/api/ai_dictation.dart';
import 'package:alera/src/rust/frb_generated.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    throw ArgumentError(
      'Expected native library, model and public test WAV paths',
    );
  }
  await RustLib.init(externalLibrary: ExternalLibrary.open(arguments[0]));
  try {
    final result = await transcribeWhisper(
      request: AiDictationRequest(
        requestId: 'dependency-upgrade-public-audio-smoke',
        audioPath: arguments[2],
        modelPath: arguments[1],
      ),
    ).timeout(const Duration(minutes: 2));
    if (!result.text.toLowerCase().contains('ask not what your country') ||
        result.detectedLanguage != 'en' ||
        result.durationMillis < 10000 ||
        result.durationMillis > 15000) {
      throw StateError('Unexpected transcription result: ${result.text}');
    }
    stdout.writeln(
      jsonEncode({
        'result': 'ALERA_WHISPER_NATIVE_SMOKE_PASS',
        'language': result.detectedLanguage,
        'durationMillis': result.durationMillis,
        'textLength': result.text.length,
      }),
    );
  } finally {
    RustLib.dispose();
  }
}
