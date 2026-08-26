import 'dart:async';
import 'dart:convert';

import 'package:alera_mobile/src/features/ai_dictation/domain/speech_capabilities.dart';
import 'package:alera_mobile/src/features/ai_dictation/domain/speech_provider_profile.dart';
import 'package:alera_mobile/src/features/ai_dictation/infra/mobile_ai_dictation_credential_store.dart';
import 'package:http/http.dart' as http;

typedef MobileDictationHttpClientFactory = http.Client Function();

class MobileOpenAiDictationResult {
  const MobileOpenAiDictationResult(this.text);

  final String text;
}

class MobileOpenAiDictationProvider {
  MobileOpenAiDictationProvider(
    this._credentials, {
    MobileDictationHttpClientFactory? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final MobileAiDictationCredentialStore _credentials;
  final MobileDictationHttpClientFactory _clientFactory;
  final Map<String, http.Client> _activeClients = <String, http.Client>{};
  final Set<String> _cancelled = <String>{};

  Future<MobileOpenAiDictationResult> transcribe({
    required String requestId,
    required String audioPath,
    required String baseUrl,
    required String model,
    required Duration timeout,
    String? language,
    String? initialPrompt,
  }) async {
    final normalizedModel = model.trim();
    if (normalizedModel.isEmpty) {
      throw ArgumentError.value(model, 'model', 'Model cannot be empty.');
    }
    final token = await _credentials.tokenFor(baseUrl);
    final profile = SpeechProviderProfile(
      id: 'mobile-direct',
      label: 'OpenAI-Compatible API',
      type: SpeechBackend.openAiCompatible,
      baseUrl: baseUrl,
      defaultModel: normalizedModel,
      timeoutSeconds: timeout.inSeconds,
    );
    final client = _clientFactory();
    _activeClients[requestId] = client;
    final multipart = http.MultipartRequest(
      'POST',
      profile.transcriptionUri(sendsToken: token != null),
    )..fields['model'] = normalizedModel;
    multipart.fields['response_format'] = 'json';
    if (token != null && token.isNotEmpty) {
      multipart.headers['Authorization'] = 'Bearer $token';
    }
    if (language?.trim().isNotEmpty == true) {
      multipart.fields['language'] = language!.trim();
    }
    if (initialPrompt?.trim().isNotEmpty == true) {
      multipart.fields['prompt'] = initialPrompt!.trim();
    }
    multipart.files.add(
      await http.MultipartFile.fromPath(
        'file',
        audioPath,
        filename: 'dictation.wav',
      ),
    );
    try {
      final response = await client.send(multipart).timeout(timeout);
      final body = await response.stream.bytesToString();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'Speech provider returned HTTP ${response.statusCode}${_errorSuffix(body)}.',
        );
      }
      final decoded = jsonDecode(body);
      final text = decoded is Map ? decoded['text'] : null;
      if (text is! String || text.trim().isEmpty) {
        throw StateError('Speech provider returned no transcription.');
      }
      return MobileOpenAiDictationResult(text.trim());
    } on TimeoutException {
      throw TimeoutException('Speech provider timed out.', timeout);
    } on Object catch (error) {
      if (_cancelled.contains(requestId)) {
        throw StateError('Dictation cancelled.');
      }
      rethrow;
    } finally {
      _activeClients.remove(requestId);
      _cancelled.remove(requestId);
      client.close();
    }
  }

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
