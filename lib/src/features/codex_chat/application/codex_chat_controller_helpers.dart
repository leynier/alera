part of 'codex_chat_controller.dart';

extension on CodexChatController {
  Future<List<CodexModelOption>> _loadModels() async {
    try {
      final payload = await _host.listModels();
      final items = _items(payload);
      final models = <CodexModelOption>[
        for (final item in items) CodexModelOption.fromJson(item),
      ];
      if (models.isNotEmpty) return models;
    } catch (_) {
      // Fall back below. The fallback is intentionally a current Codex set,
      // never a persisted model snapshot from an older app.
    }
    return const <CodexModelOption>[
      CodexModelOption(id: 'gpt-5.6-sol', label: '5.6 Sol'),
    ];
  }
}

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

List<Map<String, Object?>> _skillItems(Map<String, Object?> payload) {
  final entries = _items(payload);
  final grouped = entries.any((entry) => entry['skills'] is List);
  if (!grouped) return entries;
  return <Map<String, Object?>>[
    for (final entry in entries)
      if (entry['skills'] is List)
        for (final skill in entry['skills'] as List)
          if (skill is Map && skill['enabled'] != false)
            <String, Object?>{
              ...Map<String, Object?>.from(skill),
              if (entry['cwd'] != null) 'cwd': entry['cwd'],
            },
  ];
}

List<Map<String, Object?>> _appItems(Map<String, Object?> payload) =>
    _items(payload)
        .where(
          (app) => app['isAccessible'] != false && app['isEnabled'] != false,
        )
        .toList(growable: false);

String _supportedEffort(CodexModelOption? model, String requested) {
  final supported = model?.reasoningEfforts ?? const <String>[];
  if (supported.isEmpty || supported.contains(requested)) return requested;
  final modelDefault = model?.defaultReasoningEffort;
  if (modelDefault != null && supported.contains(modelDefault)) {
    return modelDefault;
  }
  for (final fallback in <String>['medium', 'high', 'low', 'xhigh']) {
    if (supported.contains(fallback)) return fallback;
  }
  return supported.first;
}

Map<String, Object?> _configurationPayload(CodexChatState state) =>
    <String, Object?>{
      'selectedModel': state.selectedModel,
      'reasoningEffort': state.reasoningEffort,
      'speedMode': state.speedMode,
      'permissionMode': state.permissionMode,
      'planMode': state.planMode,
      'collaborationMode': state.collaborationMode,
    };

CodexChatState _applyConfiguration(CodexChatState state, Object? value) {
  if (value is! Map) return state;
  final json = Map<String, Object?>.from(value);
  final selectedModel = _string(json['selectedModel']);
  final reasoningEffort = _string(json['reasoningEffort']);
  final speedMode = _string(json['speedMode']);
  final permissionMode = _string(json['permissionMode']);
  final collaborationMode = _string(json['collaborationMode']);
  return state.copyWith(
    selectedModel: json.containsKey('selectedModel')
        ? selectedModel
        : state.selectedModel,
    reasoningEffort: reasoningEffort ?? state.reasoningEffort,
    speedMode: speedMode == 'fast' ? 'fast' : 'normal',
    permissionMode: permissionMode == null
        ? state.permissionMode
        : _supportedPermissionMode(permissionMode),
    planMode: json['planMode'] is bool
        ? json['planMode']! as bool
        : state.planMode,
    collaborationMode: collaborationMode,
  );
}

String _supportedPermissionMode(String mode) => switch (mode) {
  'auto-review' || 'never' => mode,
  _ => 'on-request',
};

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
  final input = <Map<String, Object?>>[];
  for (final item in message.draftItems) {
    if (item.kind == CodexDraftItemKind.skill) {
      input.add(<String, Object?>{
        'type': 'skill',
        'name': item.name,
        'path': item.path,
      });
    } else if (item.kind == CodexDraftItemKind.app) {
      input.add(<String, Object?>{
        'type': 'mention',
        'name': item.name,
        'path': item.path,
      });
    }
  }
  if (skill != null) input.add(skill.$1);
  if (app != null) input.add(app.$1);

  var hasText = false;
  void addText(String text) {
    input.add(<String, Object?>{'type': 'text', 'text': text});
    hasText = true;
  }

  if (skill != null) {
    addText(skill.$2);
  } else if (app != null) {
    addText(app.$2);
  } else if (message.text.isNotEmpty) {
    addText(message.text);
  }

  final references = <({String path, String name})>[];
  final seenReferences = <String>{};
  void addReference(String path, String name) {
    final reference = codexFileReferenceText(path);
    if (!seenReferences.add(path)) return;
    for (final part in input) {
      if (part['type'] != 'text') continue;
      final text = part['text']?.toString() ?? '';
      final characterStart = _completeReferenceStart(text, reference);
      if (characterStart < 0) continue;
      final start = utf8.encode(text.substring(0, characterStart)).length;
      final elements =
          part.putIfAbsent('text_elements', () => <Map<String, Object?>>[])
              as List<Map<String, Object?>>;
      elements.add(<String, Object?>{
        'byteRange': <String, Object?>{
          'start': start,
          'end': start + utf8.encode(reference).length,
        },
        'placeholder': name,
      });
      return;
    }
    references.add((path: path, name: name));
  }

  for (final item in message.draftItems) {
    if (item.kind == CodexDraftItemKind.mention) {
      addReference(item.path, item.name);
    }
  }
  for (final attachment in message.attachments) {
    if (attachment.isImage) {
      input.add(<String, Object?>{
        'type': 'localImage',
        'path': attachment.path,
        if (attachment.detail != null) 'detail': attachment.detail,
      });
    } else if (_isAudioInput(attachment.path, attachment.mimeType)) {
      input.add(<String, Object?>{
        'type': 'localAudio',
        'path': attachment.path,
      });
    } else {
      addReference(
        attachment.path,
        attachment.displayName ?? _fileName(attachment.path),
      );
    }
  }
  input.addAll(_fileReferenceInputs(references, followsText: hasText));
  return input;
}

int _completeReferenceStart(String text, String reference) {
  var offset = 0;
  while (offset <= text.length - reference.length) {
    final match = text.indexOf(reference, offset);
    if (match < 0) return -1;
    final before = match == 0 ? null : text[match - 1];
    final end = match + reference.length;
    final after = end == text.length ? null : text[end];
    if (_isReferenceBoundary(before) && _isReferenceBoundary(after)) {
      return match;
    }
    offset = match + 1;
  }
  return -1;
}

bool _isReferenceBoundary(String? character) =>
    character == null || character.trim().isEmpty;

List<Map<String, Object?>> _fileReferenceInputs(
  List<({String path, String name})> references, {
  required bool followsText,
}) {
  final result = <Map<String, Object?>>[];
  for (var index = 0; index < references.length; index++) {
    final reference = references[index];
    final prefix = index == 0 ? (followsText ? '\n\n' : '') : '\n';
    final path = codexFileReferenceText(reference.path);
    final text = '$prefix$path';
    final start = utf8.encode(prefix).length;
    result.add(<String, Object?>{
      'type': 'text',
      'text': text,
      'text_elements': <Map<String, Object?>>[
        <String, Object?>{
          'byteRange': <String, Object?>{
            'start': start,
            'end': start + utf8.encode(path).length,
          },
          'placeholder': reference.name,
        },
      ],
    });
  }
  return result;
}

Map<String, Object?> _userMessagePresentation(CodexQueuedMessage message) {
  final attachments = <Map<String, Object?>>[];
  final seen = <String>{};
  for (final attachment in message.attachments) {
    if (!seen.add(attachment.path)) continue;
    attachments.add(<String, Object?>{
      'path': attachment.path,
      'displayName': attachment.displayName ?? _fileName(attachment.path),
      'kind': attachment.isDirectory
          ? 'directory'
          : attachment.isImage
          ? 'image'
          : 'file',
      'origin': attachment.origin.name,
      'isImage': attachment.isImage,
      'isDirectory': attachment.isDirectory,
      if (attachment.mimeType != null) 'mimeType': attachment.mimeType,
      if (attachment.sizeBytes != null) 'sizeBytes': attachment.sizeBytes,
      if (attachment.detail != null) 'detail': attachment.detail,
    });
  }
  for (final item in message.draftItems) {
    if (item.kind != CodexDraftItemKind.mention || !seen.add(item.path)) {
      continue;
    }
    attachments.add(<String, Object?>{
      'path': item.path,
      'displayName': item.name,
      'kind': 'file',
      'origin': CodexInputAttachmentOrigin.mention.name,
      'isImage': false,
      'isDirectory': false,
    });
  }
  return <String, Object?>{
    'text': message.text,
    if (attachments.isNotEmpty) 'attachments': attachments,
  };
}

String _fileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash < 0 ? normalized : normalized.substring(slash + 1);
}

bool _isAudioInput(String path, String? mimeType) {
  if (mimeType?.toLowerCase().startsWith('audio/') == true) return true;
  final lower = path.toLowerCase();
  return <String>[
    '.mp3',
    '.m4a',
    '.wav',
    '.ogg',
    '.flac',
    '.aac',
    '.opus',
  ].any(lower.endsWith);
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
