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
  final attachments = message['attachments'] is List
      ? <Map<String, Object?>>[
          for (final value in message['attachments']! as List)
            if (value is Map) Map<String, Object?>.from(value),
        ]
      : const <Map<String, Object?>>[];
  final skill = _skillInput(text, state.skills);
  final app = _appInput(text, state.apps);
  final selectedCatalogCandidates = message['catalogSelections'] is List
      ? <Map<String, Object?>>[
          for (final value in message['catalogSelections']! as List)
            if (value is Map) Map<String, Object?>.from(value),
        ]
      : const <Map<String, Object?>>[];
  final selectedCatalog = mobileCodexActiveCatalogSelections(
    text,
    selectedCatalogCandidates,
  );
  final selectedNames = <String>{
    for (final selection in selectedCatalog)
      if (selection['name'] case final String name) name,
  };
  final selectedTokenStarts = _selectedCatalogTokenStarts(
    text,
    selectedCatalog,
  );
  final catalog = _catalogInputs(
    text,
    state.skills,
    state.apps,
    excludedNames: selectedNames,
    excludedTokenStarts: selectedTokenStarts,
  );
  final input = <Map<String, Object?>>[
    if (skill != null) skill.$1,
    if (app != null) app.$1,
    ...selectedCatalog.map(mobileCodexCatalogWireSelection),
    ...catalog,
  ];
  final modelText = skill != null
      ? skill.$2
      : app != null
      ? app.$2
      : text;
  Map<String, Object?>? modelTextInput;
  var hasText = false;
  if (modelText.isNotEmpty) {
    modelTextInput = <String, Object?>{'type': 'text', 'text': modelText};
    input.add(modelTextInput);
    hasText = true;
  }
  final references = <({String path, String name})>[];
  final inlineReferences =
      <({int start, String source, String wire, String name})>[];
  final seenReferences = <String>{};
  final sourceSearchOffsets = <String, int>{};
  for (final attachment in attachments) {
    final sourcePath = attachment['path']?.toString() ?? '';
    if (sourcePath.isEmpty) continue;
    final path = _presentationAttachmentPath(
      attachment,
      fallbackCwd: state.activeCwd,
    );
    if (attachment['type'] == 'localImage') {
      input.add(<String, Object?>{
        'type': 'localImage',
        'path': path,
        if (attachment['detail'] != null) 'detail': attachment['detail'],
      });
    } else if (attachment['type'] == 'localAudio') {
      input.add(<String, Object?>{'type': 'localAudio', 'path': path});
    } else if (seenReferences.add(path)) {
      final name =
          attachment['displayName']?.toString() ??
          attachment['name']?.toString() ??
          _basename(path);
      final sourceReference = mobileCodexFileReferenceText(sourcePath);
      final wireReference = mobileCodexFileReferenceText(path);
      final characterStart = _mobileCompleteReferenceStart(
        modelText,
        sourceReference,
        start: sourceSearchOffsets[sourceReference] ?? 0,
      );
      if (characterStart >= 0) {
        sourceSearchOffsets[sourceReference] =
            characterStart + sourceReference.length;
        inlineReferences.add((
          start: characterStart,
          source: sourceReference,
          wire: wireReference,
          name: name,
        ));
      } else {
        references.add((path: path, name: name));
      }
    }
  }
  if (modelTextInput != null && inlineReferences.isNotEmpty) {
    var wireText = modelText;
    for (final reference
        in inlineReferences.toList()
          ..sort((left, right) => right.start.compareTo(left.start))) {
      wireText = wireText.replaceRange(
        reference.start,
        reference.start + reference.source.length,
        reference.wire,
      );
    }
    modelTextInput['text'] = wireText;
    final elements = <Map<String, Object?>>[];
    for (final reference in inlineReferences) {
      final precedingShift = inlineReferences
          .where((candidate) => candidate.start < reference.start)
          .fold<int>(
            0,
            (shift, candidate) =>
                shift + candidate.wire.length - candidate.source.length,
          );
      final characterStart = reference.start + precedingShift;
      final start = utf8.encode(wireText.substring(0, characterStart)).length;
      elements.add(<String, Object?>{
        'byteRange': <String, Object?>{
          'start': start,
          'end': start + utf8.encode(reference.wire).length,
        },
        'placeholder': reference.name,
      });
    }
    modelTextInput['text_elements'] = elements;
  }
  input.addAll(_mobileFileReferenceInputs(references, followsText: hasText));
  return input;
}

int _mobileCompleteReferenceStart(
  String text,
  String reference, {
  required int start,
}) {
  var offset = start;
  while (offset <= text.length - reference.length) {
    final match = text.indexOf(reference, offset);
    if (match < 0) return -1;
    final before = match == 0 ? null : text[match - 1];
    final end = match + reference.length;
    final after = end == text.length ? null : text[end];
    if ((before == null || before.trim().isEmpty) &&
        (after == null || after.trim().isEmpty)) {
      return match;
    }
    offset = match + 1;
  }
  return -1;
}

List<Map<String, Object?>> _mobileFileReferenceInputs(
  List<({String path, String name})> references, {
  required bool followsText,
}) {
  final result = <Map<String, Object?>>[];
  for (var index = 0; index < references.length; index++) {
    final reference = references[index];
    final prefix = index == 0 ? (followsText ? '\n\n' : '') : '\n';
    final path = mobileCodexFileReferenceText(reference.path);
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

Map<String, Object?> _userMessagePresentation(
  Map<String, Object?> message, {
  String? cwd,
}) {
  final rawAttachments = message['attachments'];
  final attachments = <Map<String, Object?>>[];
  final seen = <String>{};
  if (rawAttachments is List) {
    for (final value in rawAttachments) {
      if (value is! Map) continue;
      final attachment = Map<String, Object?>.from(value);
      final path = _presentationAttachmentPath(attachment, fallbackCwd: cwd);
      if (path.isEmpty || !seen.add(path)) continue;
      final type = attachment['type']?.toString() ?? 'file';
      final isDirectory = attachment['isDirectory'] == true;
      attachments.add(<String, Object?>{
        'path': path,
        'displayName':
            attachment['displayName']?.toString() ??
            attachment['name']?.toString() ??
            _basename(path),
        'kind': isDirectory
            ? 'directory'
            : type == 'localImage'
            ? 'image'
            : 'file',
        'origin': attachment['origin']?.toString() ?? 'attachment',
        'isImage': type == 'localImage',
        'isDirectory': isDirectory,
        if (attachment['mimeType'] != null) 'mimeType': attachment['mimeType'],
        if (attachment['sizeBytes'] != null)
          'sizeBytes': attachment['sizeBytes'],
        if (attachment['detail'] != null) 'detail': attachment['detail'],
      });
    }
  }
  return <String, Object?>{
    'text': message['text']?.toString() ?? '',
    if (attachments.isNotEmpty) 'attachments': attachments,
  };
}

String _presentationAttachmentPath(
  Map<String, Object?> attachment, {
  required String? fallbackCwd,
}) {
  final path = attachment['path']?.toString() ?? '';
  if (attachment['origin'] != 'mention' || _isAbsolutePresentationPath(path)) {
    return path;
  }
  final sourceCwd =
      attachment['cwd']?.toString().trim() ?? fallbackCwd?.trim() ?? '';
  if (sourceCwd.isEmpty || !_isAbsolutePresentationPath(sourceCwd)) {
    return path;
  }
  final normalizedCwd = sourceCwd.replaceAll('\\', '/');
  var normalizedPath = path.replaceAll('\\', '/');
  if (normalizedPath.startsWith('./')) {
    normalizedPath = normalizedPath.substring(2);
  }
  final prefix = normalizedCwd.endsWith('/')
      ? normalizedCwd
      : '$normalizedCwd/';
  return '$prefix$normalizedPath';
}

bool _isAbsolutePresentationPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.startsWith('/') ||
      RegExp(r'^[A-Za-z]:/').hasMatch(normalized);
}

List<Map<String, Object?>> _catalogInputs(
  String text,
  List<Map<String, Object?>> skills,
  List<Map<String, Object?>> apps, {
  Set<String> excludedNames = const <String>{},
  Set<int> excludedTokenStarts = const <int>{},
}) {
  final result = <Map<String, Object?>>[];
  final seen = <String>{};
  for (final match in RegExp(r'\$([^\s]+)').allMatches(text)) {
    if (excludedTokenStarts.contains(match.start)) continue;
    final token = match.group(1)?.trim() ?? '';
    if (token.isEmpty || excludedNames.contains(token) || !seen.add(token)) {
      continue;
    }
    final skill = skills
        .where((item) => _catalogName(item) == token)
        .firstOrNull;
    final skillPath = skill?['path']?.toString();
    if (skillPath?.isNotEmpty == true) {
      result.add(<String, Object?>{
        'type': 'skill',
        'name': token,
        'path': skillPath,
      });
      continue;
    }
    final app = apps.where((item) => _catalogName(item) == token).firstOrNull;
    final appPath = app == null ? null : _appConnectorPath(app);
    if (appPath != null) {
      result.add(<String, Object?>{
        'type': 'mention',
        'name': token,
        'path': appPath,
      });
    }
  }
  return result;
}

Set<int> _selectedCatalogTokenStarts(
  String text,
  List<Map<String, Object?>> selectedCatalog,
) {
  final starts = <int>{};
  for (final selection in selectedCatalog) {
    final name = selection['name'];
    if (name is! String || name.trim().isEmpty) continue;
    final pattern = RegExp(
      '(?:^|\\s)(\\\$${RegExp.escape(name.trim())})(?=\\s|\$)',
    );
    for (final match in pattern.allMatches(text)) {
      final token = match.group(1);
      if (token != null) {
        starts.add(match.start + match.group(0)!.indexOf(token));
      }
    }
  }
  return starts;
}

String _newClientMessageId() =>
    'alera-${DateTime.now().toUtc().microsecondsSinceEpoch}';

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
  final modelDefault = model?.defaultReasoningEffort;
  if (modelDefault != null && values.contains(modelDefault)) {
    return modelDefault;
  }
  for (final value in <String>['medium', 'high', 'low', 'xhigh']) {
    if (values.contains(value)) return value;
  }
  return values.first;
}

Map<String, Object?> _mobileConfigurationPayload(MobileCodexState state) =>
    <String, Object?>{
      'selectedModel': state.selectedModel,
      'reasoningEffort': state.reasoningEffort,
      'speedMode': state.speedMode,
      'permissionMode': state.permissionMode,
      'planMode': state.planMode,
      'collaborationMode': state.collaborationMode,
    };

MobileCodexState _applyMobileConfiguration(
  MobileCodexState state,
  Object? value,
) {
  if (value is! Map) return state;
  final json = Map<String, Object?>.from(value);
  final selectedModel = _string(json['selectedModel']);
  final reasoningEffort = _string(json['reasoningEffort']);
  final permissionMode = _string(json['permissionMode']);
  final collaborationMode = _string(json['collaborationMode']);
  return state.copyWith(
    selectedModel: selectedModel ?? state.selectedModel,
    reasoningEffort: reasoningEffort ?? state.reasoningEffort,
    speedMode: json['speedMode'] == 'fast' ? 'fast' : 'normal',
    permissionMode: switch (permissionMode) {
      'untrusted' ||
      'on-request' ||
      'auto-review' ||
      'never' => permissionMode!,
      _ => state.permissionMode,
    },
    planMode: json['planMode'] is bool
        ? json['planMode']! as bool
        : state.planMode,
    collaborationMode: collaborationMode,
  );
}

String _safeError(Object error) {
  final message = error.toString().replaceFirst('Exception: ', '').trim();
  return message.isEmpty
      ? 'Codex request failed. Check the runtime connection and retry.'
      : message;
}
