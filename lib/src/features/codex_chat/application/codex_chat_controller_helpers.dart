part of 'codex_chat_controller.dart';

List<Map<String, Object?>> _items(Map<String, Object?> payload) {
  final value =
      payload['data'] ??
      payload['items'] ??
      payload['models'] ??
      payload['apps'] ??
      payload['skills'] ??
      payload['collaborationModes'] ??
      payload['modes'];
  if (value is! List) return const <Map<String, Object?>>[];
  return <Map<String, Object?>>[
    for (final item in value)
      if (item is Map) Map<String, Object?>.from(item),
  ];
}

String _supportedEffort(CodexModelOption? model, String requested) {
  final supported = model?.reasoningEfforts ?? const <String>[];
  if (supported.isEmpty || supported.contains(requested)) return requested;
  for (final fallback in <String>['medium', 'high', 'low', 'xhigh']) {
    if (supported.contains(fallback)) return fallback;
  }
  return supported.first;
}

String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

String _safeError(Object error) {
  final message = error.toString().replaceFirst('Exception: ', '').trim();
  return message.isEmpty ? 'Codex request failed.' : message;
}

String _newClientMessageId() =>
    'alera-${DateTime.now().toUtc().microsecondsSinceEpoch}';

List<Map<String, Object?>> _buildInput(
  CodexQueuedMessage message,
  CodexChatState state,
) {
  final skill = _skillInput(message.text, state.skills);
  final app = _appInput(message.text, state.apps);
  return <Map<String, Object?>>[
    if (skill != null) skill.$1,
    if (app != null) app.$1,
    if (skill != null) <String, Object?>{'type': 'text', 'text': skill.$2},
    if (app != null) <String, Object?>{'type': 'text', 'text': app.$2},
    if (message.text.isNotEmpty && skill == null && app == null)
      <String, Object?>{'type': 'text', 'text': message.text},
    for (final attachment in message.attachments)
      if (attachment.isImage)
        <String, Object?>{
          'type': 'localImage',
          'path': attachment.path,
          if (attachment.detail != null) 'detail': attachment.detail,
        }
      else
        <String, Object?>{
          'type': 'mention',
          'name': attachment.displayName ?? _basename(attachment.path),
          'path': attachment.path,
        },
    ..._mentionInputs(message.text),
  ];
}

(Map<String, Object?>, String)? _appInput(
  String text,
  List<Map<String, Object?>> apps,
) {
  final match = RegExp(
    r'^/app\s+([^\s]+)(?:\s+(.+))?$',
    dotAll: true,
  ).firstMatch(text);
  if (match == null) return null;
  final name = match.group(1)!;
  for (final app in apps) {
    final slug = _catalogName(app);
    final matches = <String?>[
      app['name']?.toString(),
      app['slug']?.toString(),
      app['id']?.toString(),
      app['appId']?.toString(),
      app['connectorId']?.toString(),
    ].contains(name);
    if (!matches || slug.isEmpty) continue;
    final connector = _appConnectorPath(app);
    if (connector == null) continue;
    return (
      <String, Object?>{'type': 'mention', 'name': slug, 'path': connector},
      _wireCatalogText(slug, match.group(2)),
    );
  }
  return null;
}

List<Map<String, Object?>> _mentionInputs(String text) {
  final mentions = <Map<String, Object?>>[];
  final seen = <String>{};
  for (final match in RegExp(r'@([^\s]+)').allMatches(text)) {
    final path = match.group(1)?.trim() ?? '';
    if (path.isEmpty || !seen.add(path) || path.startsWith('@')) continue;
    mentions.add(<String, Object?>{
      'type': 'mention',
      'name': _basename(path),
      'path': path,
    });
  }
  return mentions;
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash < 0 ? normalized : normalized.substring(slash + 1);
}

(Map<String, Object?>, String)? _skillInput(
  String text,
  List<Map<String, Object?>> skills,
) {
  final match = RegExp(
    r'^/skill\s+([^\s]+)(?:\s+(.+))?$',
    dotAll: true,
  ).firstMatch(text);
  if (match == null) return null;
  final name = match.group(1)!;
  for (final skill in skills) {
    final skillName = _catalogName(skill);
    final path = skill['path']?.toString();
    if (skillName == name && path != null && path.isNotEmpty) {
      return (
        <String, Object?>{'type': 'skill', 'name': skillName, 'path': path},
        _wireCatalogText(skillName, match.group(2)),
      );
    }
  }
  return null;
}

String _catalogName(Map<String, Object?> item) => _firstNonEmpty(<Object?>[
  item['slug'],
  item['name'],
  item['id'],
  item['appId'],
]);

String? _appConnectorPath(Map<String, Object?> app) {
  final path = app['path']?.toString();
  if (path != null && path.startsWith('app://')) return path;
  final connector = _firstNonEmpty(<Object?>[
    app['connectorId'],
    app['connector_id'],
    app['appId'],
    app['id'],
  ]);
  return connector.isEmpty ? null : 'app://$connector';
}

String _wireCatalogText(String name, String? remainder) {
  final suffix = remainder?.trim() ?? '';
  return suffix.isEmpty ? '\$$name' : '\$$name $suffix';
}

String _firstNonEmpty(Iterable<Object?> values) {
  for (final value in values) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return '';
}

Map<String, Object?> _permissionSubset(Object? value) {
  if (value is! Map) return const <String, Object?>{};
  final source = Map<String, Object?>.from(value);
  final result = <String, Object?>{};
  final fileSystem = _permissionObject(source['fileSystem'], const <String>[
    'entries',
    'globScanMaxDepth',
    'read',
    'write',
  ]);
  final network = _permissionObject(source['network'], const <String>[
    'enabled',
  ]);
  if (fileSystem.isNotEmpty) result['fileSystem'] = fileSystem;
  if (network.isNotEmpty) result['network'] = network;
  return result;
}

Map<String, Object?> _permissionObject(Object? value, List<String> keys) {
  if (value is! Map) return const <String, Object?>{};
  final source = Map<String, Object?>.from(value);
  return <String, Object?>{
    for (final key in keys)
      if (source.containsKey(key)) key: source[key],
  };
}
