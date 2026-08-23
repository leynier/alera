import 'speech_capabilities.dart';

class SpeechProviderProfile {
  const SpeechProviderProfile({
    required this.id,
    required this.label,
    required this.type,
    required this.baseUrl,
    this.defaultModel,
    this.configuredModels = const <String>[],
    this.timeoutSeconds = 60,
  });

  final String id;
  final String label;
  final SpeechBackend type;
  final String baseUrl;
  final String? defaultModel;
  final List<String> configuredModels;
  final int timeoutSeconds;

  Uri transcriptionUri() {
    final uri = Uri.parse(baseUrl.trim());
    if (!uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('Speech provider URL must include a host.');
    }
    final segments = <String>[...uri.pathSegments];
    while (segments.isNotEmpty && segments.last.isEmpty) {
      segments.removeLast();
    }
    if (segments.isEmpty || segments.last != 'v1') segments.add('v1');
    segments.add('audio');
    segments.add('transcriptions');
    return uri.replace(pathSegments: segments);
  }
}
