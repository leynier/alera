part of 'mobile_codex_controller.dart';

List<MobileCodexModelOption> _modelItems(Map<String, Object?> payload) {
  final value = payload['data'] ?? payload['items'] ?? payload['models'];
  return value is List
      ? <MobileCodexModelOption>[
          for (final item in value) MobileCodexModelOption.fromJson(item),
        ]
      : const <MobileCodexModelOption>[];
}

List<Map<String, Object?>> _input(
  Map<String, Object?> message,
  MobileCodexState state,
) {
  final text = message['text']?.toString() ?? '';
  final attachments = message['attachments'];
  final skill = _skillInput(text, state.skills);
  final app = _appInput(text, state.apps);
  return <Map<String, Object?>>[
    if (skill != null) skill.$1,
    if (app != null) app.$1,
    if (text.isNotEmpty && skill == null && app == null)
      <String, Object?>{'type': 'text', 'text': text},
    if (skill != null && skill.$2.isNotEmpty)
      <String, Object?>{'type': 'text', 'text': skill.$2},
    if (app != null && app.$2.isNotEmpty)
      <String, Object?>{'type': 'text', 'text': app.$2},
    if (attachments is List)
      for (final attachment in attachments)
        if (attachment is Map) Map<String, Object?>.from(attachment),
    ..._mentionInputs(text),
  ];
}

List<Map<String, Object?>> _mentionInputs(String text) {
  final result = <Map<String, Object?>>[];
  final seen = <String>{};
  for (final match in RegExp(r'@([^\s]+)').allMatches(text)) {
    final path = match.group(1)?.trim() ?? '';
    if (path.isEmpty || !seen.add(path)) continue;
    result.add(<String, Object?>{
      'type': 'mention',
      'name': _basename(path),
      'path': path,
    });
  }
  return result;
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash < 0 ? normalized : normalized.substring(slash + 1);
}

(Map<String, Object?>, String)? _skillInput(
  String text,
  List<Map<String, Object?>> skills,
) => _catalogInput(text, '/skill', skills, 'skill');

(Map<String, Object?>, String)? _appInput(
  String text,
  List<Map<String, Object?>> apps,
) => _catalogInput(text, '/app', apps, 'app');

(Map<String, Object?>, String)? _catalogInput(
  String text,
  String command,
  List<Map<String, Object?>> items,
  String type,
) {
  final pattern =
      '^${RegExp.escape(command)}\\s+([^\\s]+)(?:\\s+(.+))?'
      r'$';
  final match = RegExp(pattern, dotAll: true).firstMatch(text);
  if (match == null) return null;
  final name = match.group(1)!;
  for (final item in items) {
    if (item['name']?.toString() != name) continue;
    final path = item['path']?.toString();
    return (
      <String, Object?>{
        'type': type,
        'name': name,
        if (path != null && path.isNotEmpty) 'path': path,
      },
      match.group(2)?.trim() ?? '',
    );
  }
  return null;
}

String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

String _supportedEffort(MobileCodexModelOption? model, String requested) {
  final values = model?.reasoningEfforts ?? const <String>[];
  if (values.isEmpty || values.contains(requested)) return requested;
  for (final value in <String>['medium', 'high', 'low', 'xhigh']) {
    if (values.contains(value)) return value;
  }
  return values.first;
}

String _safeError(Object error) {
  final message = error.toString().replaceFirst('Exception: ', '').trim();
  return message.isEmpty
      ? 'Codex request failed. Check the runtime connection and retry.'
      : message;
}
