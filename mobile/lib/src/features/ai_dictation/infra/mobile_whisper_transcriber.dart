import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

typedef _TranscribeNative = Pointer<Utf8> Function(Pointer<Utf8> request);
typedef _TranscribeDart = Pointer<Utf8> Function(Pointer<Utf8> request);
typedef _CancelNative = Void Function(Pointer<Utf8> requestId);
typedef _CancelDart = void Function(Pointer<Utf8> requestId);
typedef _FreeNative = Void Function(Pointer<Utf8> value);
typedef _FreeDart = void Function(Pointer<Utf8> value);

class const MobileWhisperResult({
  required final String text,
  required final Duration duration,
  final String? detectedLanguage,
});

class const MobileWhisperException(final String kind, final String message)
    implements Exception {
  @override
  String toString() => message;
}

class MobileWhisperTranscriber {
  Future<MobileWhisperResult> transcribe({
    required String requestId,
    required String audioPath,
    required String modelPath,
    String? language,
    String? initialPrompt,
  }) async {
    final payload = jsonEncode(<String, Object?>{
      'requestId': requestId,
      'audioPath': audioPath,
      'modelPath': modelPath,
      'language': language,
      'initialPrompt': initialPrompt,
    });
    final response = await Isolate.run(() => _transcribe(payload));
    final error = response['error'];
    if (error is Map) {
      throw MobileWhisperException(
        error['kind']?.toString() ?? 'inference',
        error['message']?.toString() ?? 'Whisper transcription failed.',
      );
    }
    final result = Map<String, Object?>.from(response['result'] as Map);
    return MobileWhisperResult(
      text: result['text']!.toString(),
      duration: Duration(
        milliseconds: (result['durationMillis'] as num?)?.toInt() ?? 0,
      ),
      detectedLanguage: result['detectedLanguage']?.toString(),
    );
  }

  void cancel(String requestId) {
    final library = _library();
    final cancel = library.lookupFunction<_CancelNative, _CancelDart>(
      'alera_mobile_whisper_cancel',
    );
    final nativeId = requestId.toNativeUtf8();
    try {
      cancel(nativeId);
    } finally {
      malloc.free(nativeId);
    }
  }
}

Map<String, Object?> _transcribe(String payload) {
  final library = _library();
  final transcribe = library.lookupFunction<_TranscribeNative, _TranscribeDart>(
    'alera_mobile_whisper_transcribe',
  );
  final free = library.lookupFunction<_FreeNative, _FreeDart>(
    'alera_mobile_whisper_string_free',
  );
  final nativePayload = payload.toNativeUtf8();
  Pointer<Utf8>? nativeResponse;
  try {
    nativeResponse = transcribe(nativePayload);
    return Map<String, Object?>.from(
      jsonDecode(nativeResponse.toDartString()) as Map,
    );
  } finally {
    malloc.free(nativePayload);
    if (nativeResponse != null) free(nativeResponse);
  }
}

DynamicLibrary _library() {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libalera_mobile_native.so');
  }
  if (Platform.isIOS) return DynamicLibrary.process();
  throw UnsupportedError('Local Whisper is available on Android and iOS.');
}
