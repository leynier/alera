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
    if (skill != null) <String, Object?>{'type': 'text', 'text': skill.$2},
    if (app != null) <String, Object?>{'type': 'text', 'text': app.$2},
    if (text.isNotEmpty && skill == null && app == null)
      <String, Object?>{'type': 'text', 'text': text},
    if (attachments is List)
      for (final attachment in attachments)
        if (attachment is Map) Map<String, Object?>.from(attachment),
    ..._mentionInputs(text),
  ];
}

String _newClientMessageId() =>
    'alera-${DateTime.now().toUtc().microsecondsSinceEpoch}';

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
