import 'package:alera/src/features/ai_dictation/domain/ai_dictation_error.dart';

Uri openAiCompatibleTranscriptionUri(
  String baseUrl, {
  required bool sendsToken,
}) {
  final uri = Uri.tryParse(baseUrl.trim());
  if (uri == null ||
      !uri.hasAuthority ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    throw const AiDictationException(
      AiDictationErrorKind.invalidRequest,
      'Speech provider base URL must use HTTP or HTTPS.',
    );
  }
  if (sendsToken && uri.scheme != 'https' && !_isLoopback(uri.host)) {
    throw const AiDictationException(
      AiDictationErrorKind.invalidRequest,
      'A token can only be sent over HTTPS or to a loopback address.',
    );
  }
  final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  final endpointPath = path.endsWith('/audio/transcriptions')
      ? path
      : path.isEmpty
      ? '/v1/audio/transcriptions'
      : '$path/audio/transcriptions';
  return uri.replace(path: endpointPath, fragment: null);
}

String openAiCompatibleProviderOrigin(String baseUrl) {
  final uri = openAiCompatibleTranscriptionUri(baseUrl, sendsToken: false);
  final defaultPort =
      (uri.scheme == 'https' && uri.port == 443) ||
      (uri.scheme == 'http' && uri.port == 80);
  return '${uri.scheme}://${uri.host}${defaultPort ? '' : ':${uri.port}'}';
}

bool _isLoopback(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1';
}
