import 'speech_capabilities.dart';

class const SpeechProviderProfile({
  required final String id,
  required final String label,
  required final SpeechBackend type,
  required final String baseUrl,
  final String? defaultModel,
  final List<String> configuredModels = const <String>[],
  final int timeoutSeconds = 60,
}) {
  Uri transcriptionUri({bool sendsToken = false}) {
    final uri = Uri.parse(baseUrl.trim());
    if (!uri.hasAuthority || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException(
        'Speech provider URL must use HTTP or HTTPS.',
      );
    }
    if (sendsToken && uri.scheme != 'https' && !_isLoopback(uri.host)) {
      throw const FormatException(
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

  String providerOrigin() {
    final uri = transcriptionUri();
    final defaultPort =
        (uri.scheme == 'https' && uri.port == 443) ||
        (uri.scheme == 'http' && uri.port == 80);
    return '${uri.scheme}://${uri.host}${defaultPort ? '' : ':${uri.port}'}';
  }
}

bool _isLoopback(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1';
}
