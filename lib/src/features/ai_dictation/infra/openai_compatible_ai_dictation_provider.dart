import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:alera/src/features/ai_dictation/domain/ai_dictation_error.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_provider.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_request.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_result.dart';

class OpenAiCompatibleAiDictationProvider implements AiDictationProvider {
  OpenAiCompatibleAiDictationProvider({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  @override
  String get id => 'openai-compatible';

  @override
  Future<AiDictationResult> transcribe(AiDictationRequest request) async {
    final baseUrl = request.providerBaseUrl?.trim();
    final model = request.providerModel?.trim();
    if (baseUrl == null || baseUrl.isEmpty || model == null || model.isEmpty) {
      throw const AiDictationException(
        AiDictationErrorKind.invalidRequest,
        'Configure a speech provider URL and model before using remote fallback.',
      );
    }
    final uri = _transcriptionUri(baseUrl);
    final multipart = http.MultipartRequest('POST', uri)
      ..fields['model'] = model
      ..fields['response_format'] = 'json';
    final apiKey = request.providerApiKey?.trim();
    if (apiKey != null && apiKey.isNotEmpty) {
      multipart.headers['Authorization'] = 'Bearer $apiKey';
    }
    if (request.language?.trim().isNotEmpty == true) {
      multipart.fields['language'] = request.language!.trim();
    }
    if (request.initialPrompt?.trim().isNotEmpty == true) {
      multipart.fields['prompt'] = request.initialPrompt!.trim();
    }
    multipart.files.add(
      await http.MultipartFile.fromPath(
        'file',
        request.audioPath,
        filename: 'dictation.wav',
      ),
    );
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _client
          .send(multipart)
          .timeout(request.timeout ?? const Duration(seconds: 60));
      final body = await response.stream.bytesToString();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiDictationException(
          AiDictationErrorKind.transcription,
          'Speech provider returned HTTP ${response.statusCode}.',
          cause: body,
        );
      }
      final decoded = jsonDecode(body);
      final text = decoded is Map ? decoded['text'] : null;
      if (text is! String || text.trim().isEmpty) {
        throw const AiDictationException(
          AiDictationErrorKind.transcription,
          'Speech provider returned no transcription.',
        );
      }
      return AiDictationResult(
        text: text.trim(),
        providerId: id,
        elapsed: stopwatch.elapsed,
        duration: Duration.zero,
      );
    } on TimeoutException catch (error) {
      throw AiDictationException(
        AiDictationErrorKind.transcription,
        'Speech provider timed out.',
        cause: error,
      );
    } on AiDictationException {
      rethrow;
    } on Object catch (error) {
      throw AiDictationException(
        AiDictationErrorKind.transcription,
        'Speech provider request failed.',
        cause: error,
      );
    } finally {
      stopwatch.stop();
    }
  }

  Uri _transcriptionUri(String baseUrl) {
    final parsed = Uri.parse(baseUrl);
    final path = parsed.path.endsWith('/')
        ? parsed.path.substring(0, parsed.path.length - 1)
        : parsed.path;
    final normalizedPath = path.endsWith('/v1') ? path : '$path/v1';
    return parsed.replace(path: '$normalizedPath/audio/transcriptions');
  }

  @override
  Future<void> cancel(String requestId) async {}

  void dispose() => _client.close();
}
