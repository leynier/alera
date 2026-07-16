part of 'ai_text_generation_service.dart';

class _AiTextCommandPlan {
  const _AiTextCommandPlan({
    required this.binary,
    required this.args,
    required this.stdinPayload,
    required this.label,
    this.environmentOverrides = const <String, String>{},
    this.promptDirectory,
  });

  final String binary;
  final List<String> args;
  final String? stdinPayload;
  final String label;
  final Map<String, String> environmentOverrides;
  final Directory? promptDirectory;

  Future<void> dispose() async {
    final directory = promptDirectory;
    if (directory == null) {
      return;
    }
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {}
  }
}
