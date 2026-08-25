import 'dart:async';
import 'dart:convert';

import 'package:alera/src/features/ai_dictation/domain/ai_dictation_error.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_provider.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_request.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_result.dart';
import 'package:alera/src/features/ai_dictation/infra/direct_ai_dictation_credential_store.dart';
import 'package:alera/src/features/ai_dictation/infra/openai_compatible_endpoint.dart';
import 'package:http/http.dart' as http;

typedef AiDictationHttpClientFactory = http.Client Function();

class OpenAiCompatibleAiDictationProvider implements AiDictationProvider {
  OpenAiCompatibleAiDictationProvider(
    this._credentials, {
    AiDictationHttpClientFactory? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final DirectAiDictationCredentialStore _credentials;
  final AiDictationHttpClientFactory _clientFactory;
  final Map<String, http.Client> _activeClients = <String, http.Client>{};
  final Set<String> _cancelled = <String>{};

  @override
  String get id => 'openai-compatible-direct';

  @override
  Future<AiDictationResult> transcribe(AiDictationRequest request) async {
    final baseUrl = request.providerBaseUrl?.trim();
    final model = request.providerModel?.trim();
    if (baseUrl == null || baseUrl.isEmpty || model == null || model.isEmpty) {
      throw const AiDictationException(
        AiDictationErrorKind.invalidRequest,
        'Configure a speech provider URL and model before transcribing.',
      );
    }
    final token = await _credentials.tokenFor(baseUrl);
    final uri = openAiCompatibleTranscriptionUri(
      baseUrl,
      sendsToken: token != null,
    );
    final client = _clientFactory();
    _activeClients[request.requestId] = client;
    final multipart = http.MultipartRequest('POST', uri)
      ..fields['model'] = model
      ..fields['response_format'] = 'json';
    if (token != null && token.isNotEmpty) {
      multipart.headers['Authorization'] = 'Bearer $token';
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
      final response = await client
          .send(multipart)
          .timeout(request.timeout ?? const Duration(seconds: 60));
      final body = await response.stream.bytesToString();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiDictationException(
          AiDictationErrorKind.transcription,
          'Speech provider returned HTTP ${response.statusCode}${_errorSuffix(body)}.',
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
      if (_cancelled.contains(request.requestId)) {
        throw AiDictationException(
          AiDictationErrorKind.cancelled,
          'Dictation cancelled.',
          cause: error,
        );
      }
      throw AiDictationException(
        AiDictationErrorKind.transcription,
        'Speech provider request failed.',
        cause: error,
      );
    } finally {
      stopwatch.stop();
      _activeClients.remove(request.requestId);
      _cancelled.remove(request.requestId);
      client.close();
    }
  }

  @override
  Future<void> cancel(String requestId) async {
    final client = _activeClients[requestId];
    if (client == null) return;
    _cancelled.add(requestId);
    client.close();
  }
}

String _errorSuffix(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded case {
      'error': {'message': final String message},
    } when message.trim().isNotEmpty) {
      return ': ${message.trim()}';
    }
  } on FormatException {
    return '';
  }
  return '';
}
