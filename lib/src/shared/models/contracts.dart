enum AppServerConnectionState { disconnected, starting, connected, error }

enum CodexReviewDelivery { inline, detached }

extension CodexReviewDeliveryWire on CodexReviewDelivery {
  String get wireValue {
    switch (this) {
      case CodexReviewDelivery.inline:
        return 'inline';
      case CodexReviewDelivery.detached:
        return 'detached';
    }
  }
}

CodexReviewDelivery codexReviewDeliveryFromWire(String wireValue) {
  switch (wireValue) {
    case 'inline':
      return CodexReviewDelivery.inline;
    case 'detached':
      return CodexReviewDelivery.detached;
  }
  throw StateError('Unknown review delivery: $wireValue');
}

enum CodexCollaborationModeKind { defaultMode, plan }

extension CodexCollaborationModeKindWire on CodexCollaborationModeKind {
  String get wireValue {
    switch (this) {
      case CodexCollaborationModeKind.defaultMode:
        return 'default';
      case CodexCollaborationModeKind.plan:
        return 'plan';
    }
  }
}

CodexCollaborationModeKind codexCollaborationModeKindFromWire(
  String wireValue,
) {
  switch (wireValue) {
    case 'default':
      return CodexCollaborationModeKind.defaultMode;
    case 'plan':
      return CodexCollaborationModeKind.plan;
  }
  throw StateError('Unknown collaboration mode kind: $wireValue');
}

sealed class CodexReviewTarget {
  const CodexReviewTarget();

  Map<String, dynamic> toJson();
}

class ReviewTarget extends CodexReviewTarget {
  const ReviewTarget.uncommittedChanges()
    : _delegate = const CodexReviewUncommittedChangesTarget();

  ReviewTarget.baseBranch(String branch)
    : _delegate = CodexReviewBaseBranchTarget(branch: branch);

  ReviewTarget.commit(String sha, {String? title})
    : _delegate = CodexReviewCommitTarget(sha: sha, title: title);

  ReviewTarget.custom(String instructions)
    : _delegate = CodexReviewCustomTarget(instructions: instructions);

  final CodexReviewTarget _delegate;

  @override
  Map<String, dynamic> toJson() => _delegate.toJson();
}

class CodexReviewUncommittedChangesTarget extends CodexReviewTarget {
  const CodexReviewUncommittedChangesTarget();

  @override
  Map<String, dynamic> toJson() {
    return const <String, dynamic>{'type': 'uncommittedChanges'};
  }
}

class CodexReviewBaseBranchTarget extends CodexReviewTarget {
  const CodexReviewBaseBranchTarget({required this.branch});

  final String branch;

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{'type': 'baseBranch', 'branch': branch};
  }
}

class CodexReviewCommitTarget extends CodexReviewTarget {
  const CodexReviewCommitTarget({required this.sha, this.title});

  final String sha;
  final String? title;

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{'type': 'commit', 'sha': sha, 'title': title};
  }
}

class CodexReviewCustomTarget extends CodexReviewTarget {
  const CodexReviewCustomTarget({required this.instructions});

  final String instructions;

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{'type': 'custom', 'instructions': instructions};
  }
}

class CodexTurnSummary {
  const CodexTurnSummary({required this.id, required this.status, this.error});

  final String id;
  final String status;
  final String? error;

  factory CodexTurnSummary.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final status = json['status']?.toString();
    if (id == null || id.isEmpty) {
      throw StateError('Turn is missing an id');
    }
    if (status == null || status.isEmpty) {
      throw StateError('Turn is missing a status');
    }

    final errorMap = _asMap(json['error']);
    return CodexTurnSummary(
      id: id,
      status: status,
      error: errorMap == null ? null : errorMap['message']?.toString(),
    );
  }
}

class CodexReviewStartResult {
  const CodexReviewStartResult({
    required this.turn,
    required this.reviewThreadId,
  });

  final CodexTurnSummary turn;
  final String reviewThreadId;

  factory CodexReviewStartResult.fromJson(Map<String, dynamic> json) {
    final turnJson = _asMap(json['turn']);
    final reviewThreadId = json['reviewThreadId']?.toString();
    if (turnJson == null) {
      throw StateError('review/start result is missing turn');
    }
    if (reviewThreadId == null || reviewThreadId.isEmpty) {
      throw StateError('review/start result is missing reviewThreadId');
    }
    return CodexReviewStartResult(
      turn: CodexTurnSummary.fromJson(turnJson),
      reviewThreadId: reviewThreadId,
    );
  }
}

class CodexCollaborationModeSettings {
  const CodexCollaborationModeSettings({
    required this.model,
    required this.reasoningEffort,
    required this.developerInstructions,
  });

  final String model;
  final String? reasoningEffort;
  final String? developerInstructions;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'model': model,
      'reasoning_effort': reasoningEffort,
      'developer_instructions': developerInstructions,
    };
  }

  factory CodexCollaborationModeSettings.fromJson(Map<String, dynamic> json) {
    final model = json['model']?.toString();
    if (model == null || model.isEmpty) {
      throw StateError('Collaboration mode settings are missing model');
    }
    return CodexCollaborationModeSettings(
      model: model,
      reasoningEffort: json['reasoning_effort']?.toString(),
      developerInstructions: json['developer_instructions']?.toString(),
    );
  }
}

class CodexCollaborationMode {
  const CodexCollaborationMode({required this.kind, required this.settings});

  final CodexCollaborationModeKind kind;
  final CodexCollaborationModeSettings settings;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'mode': kind.wireValue,
      'settings': settings.toJson(),
    };
  }

  factory CodexCollaborationMode.fromJson(Map<String, dynamic> json) {
    final kind = json['mode']?.toString();
    final settingsJson = _asMap(json['settings']);
    if (kind == null || kind.isEmpty) {
      throw StateError('Collaboration mode is missing mode');
    }
    if (settingsJson == null) {
      throw StateError('Collaboration mode is missing settings');
    }
    return CodexCollaborationMode(
      kind: codexCollaborationModeKindFromWire(kind),
      settings: CodexCollaborationModeSettings.fromJson(settingsJson),
    );
  }
}

class CodexCollaborationModePreset {
  const CodexCollaborationModePreset({
    required this.name,
    this.kind,
    this.model,
    this.reasoningEffort,
  });

  final String name;
  final CodexCollaborationModeKind? kind;
  final String? model;
  final String? reasoningEffort;

  factory CodexCollaborationModePreset.fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString();
    if (name == null || name.isEmpty) {
      throw StateError('Collaboration mode preset is missing name');
    }
    final wireKind = json['mode']?.toString();
    return CodexCollaborationModePreset(
      name: name,
      kind: wireKind == null || wireKind.isEmpty
          ? null
          : codexCollaborationModeKindFromWire(wireKind),
      model: json['model']?.toString(),
      reasoningEffort: json['reasoning_effort']?.toString(),
    );
  }
}

class CodexSkillsListExtraRootsForCwd {
  const CodexSkillsListExtraRootsForCwd({
    required this.cwd,
    required this.extraUserRoots,
  });

  final String cwd;
  final List<String> extraUserRoots;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'cwd': cwd, 'extraUserRoots': extraUserRoots};
  }

  factory CodexSkillsListExtraRootsForCwd.fromJson(Map<String, dynamic> json) {
    final cwd = json['cwd']?.toString();
    if (cwd == null || cwd.isEmpty) {
      throw StateError('Skills extra roots entry is missing cwd');
    }
    return CodexSkillsListExtraRootsForCwd(
      cwd: cwd,
      extraUserRoots: _stringList(json['extraUserRoots']),
    );
  }
}

class CodexSkillInterface {
  const CodexSkillInterface({
    this.displayName,
    this.shortDescription,
    this.iconSmall,
    this.iconLarge,
    this.brandColor,
    this.defaultPrompt,
  });

  final String? displayName;
  final String? shortDescription;
  final String? iconSmall;
  final String? iconLarge;
  final String? brandColor;
  final String? defaultPrompt;

  factory CodexSkillInterface.fromJson(Map<String, dynamic> json) {
    return CodexSkillInterface(
      displayName: json['displayName']?.toString(),
      shortDescription: json['shortDescription']?.toString(),
      iconSmall: json['iconSmall']?.toString(),
      iconLarge: json['iconLarge']?.toString(),
      brandColor: json['brandColor']?.toString(),
      defaultPrompt: json['defaultPrompt']?.toString(),
    );
  }
}

class CodexSkillMetadata {
  const CodexSkillMetadata({
    required this.name,
    required this.description,
    required this.path,
    required this.scope,
    required this.enabled,
    this.shortDescription,
    this.interface,
  });

  final String name;
  final String description;
  final String path;
  final String scope;
  final bool enabled;
  final String? shortDescription;
  final CodexSkillInterface? interface;

  factory CodexSkillMetadata.fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString();
    final description = json['description']?.toString();
    final path = json['path']?.toString();
    final scope = json['scope']?.toString();
    final enabled = json['enabled'];
    if (name == null || name.isEmpty) {
      throw StateError('Skill metadata is missing name');
    }
    if (description == null) {
      throw StateError('Skill metadata is missing description');
    }
    if (path == null || path.isEmpty) {
      throw StateError('Skill metadata is missing path');
    }
    if (scope == null || scope.isEmpty) {
      throw StateError('Skill metadata is missing scope');
    }
    if (enabled is! bool) {
      throw StateError('Skill metadata is missing enabled');
    }
    final interfaceJson = _asMap(json['interface']);
    return CodexSkillMetadata(
      name: name,
      description: description,
      path: path,
      scope: scope,
      enabled: enabled,
      shortDescription: json['shortDescription']?.toString(),
      interface: interfaceJson == null
          ? null
          : CodexSkillInterface.fromJson(interfaceJson),
    );
  }
}

class CodexSkillErrorInfo {
  const CodexSkillErrorInfo({required this.path, required this.message});

  final String path;
  final String message;

  factory CodexSkillErrorInfo.fromJson(Map<String, dynamic> json) {
    final path = json['path']?.toString();
    final message = json['message']?.toString();
    if (path == null || path.isEmpty) {
      throw StateError('Skill error is missing path');
    }
    if (message == null || message.isEmpty) {
      throw StateError('Skill error is missing message');
    }
    return CodexSkillErrorInfo(path: path, message: message);
  }
}

class CodexSkillsListEntry {
  const CodexSkillsListEntry({
    required this.cwd,
    required this.skills,
    required this.errors,
  });

  final String cwd;
  final List<CodexSkillMetadata> skills;
  final List<CodexSkillErrorInfo> errors;

  factory CodexSkillsListEntry.fromJson(Map<String, dynamic> json) {
    final cwd = json['cwd']?.toString();
    if (cwd == null || cwd.isEmpty) {
      throw StateError('skills/list entry is missing cwd');
    }
    return CodexSkillsListEntry(
      cwd: cwd,
      skills: _mapList(
        json['skills'],
        (item) => CodexSkillMetadata.fromJson(item),
      ),
      errors: _mapList(
        json['errors'],
        (item) => CodexSkillErrorInfo.fromJson(item),
      ),
    );
  }
}

class CodexAppInfo {
  const CodexAppInfo({
    required this.id,
    required this.name,
    required this.isAccessible,
    required this.isEnabled,
    required this.pluginDisplayNames,
    this.description,
    this.logoUrl,
    this.logoUrlDark,
    this.distributionChannel,
    this.branding,
    this.appMetadata,
    this.labels,
    this.installUrl,
  });

  final String id;
  final String name;
  final String? description;
  final String? logoUrl;
  final String? logoUrlDark;
  final String? distributionChannel;
  final Map<String, dynamic>? branding;
  final Map<String, dynamic>? appMetadata;
  final Map<String, String>? labels;
  final String? installUrl;
  final bool isAccessible;
  final bool isEnabled;
  final List<String> pluginDisplayNames;

  factory CodexAppInfo.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final name = json['name']?.toString();
    final isAccessible = json['isAccessible'];
    final isEnabled = json['isEnabled'];
    if (id == null || id.isEmpty) {
      throw StateError('App info is missing id');
    }
    if (name == null || name.isEmpty) {
      throw StateError('App info is missing name');
    }
    if (isAccessible is! bool) {
      throw StateError('App info is missing isAccessible');
    }
    if (isEnabled is! bool) {
      throw StateError('App info is missing isEnabled');
    }
    return CodexAppInfo(
      id: id,
      name: name,
      description: json['description']?.toString(),
      logoUrl: json['logoUrl']?.toString(),
      logoUrlDark: json['logoUrlDark']?.toString(),
      distributionChannel: json['distributionChannel']?.toString(),
      branding: _asMap(json['branding']),
      appMetadata: _asMap(json['appMetadata']),
      labels: _stringMap(json['labels']),
      installUrl: json['installUrl']?.toString(),
      isAccessible: isAccessible,
      isEnabled: isEnabled,
      pluginDisplayNames: _stringList(json['pluginDisplayNames']),
    );
  }
}

class CodexAppsPage {
  const CodexAppsPage({required this.data, required this.nextCursor});

  final List<CodexAppInfo> data;
  final String? nextCursor;

  factory CodexAppsPage.fromJson(Map<String, dynamic> json) {
    return CodexAppsPage(
      data: _mapList(json['data'], (item) => CodexAppInfo.fromJson(item)),
      nextCursor: json['nextCursor']?.toString(),
    );
  }
}

class CodexThreadNameUpdatedNotification {
  const CodexThreadNameUpdatedNotification({
    required this.threadId,
    this.threadName,
  });

  final String threadId;
  final String? threadName;

  factory CodexThreadNameUpdatedNotification.fromJson(
    Map<String, dynamic> json,
  ) {
    final threadId = json['threadId']?.toString();
    if (threadId == null || threadId.isEmpty) {
      throw StateError('thread/name/updated is missing threadId');
    }
    return CodexThreadNameUpdatedNotification(
      threadId: threadId,
      threadName: json['threadName']?.toString(),
    );
  }
}

class SessionCreateRequest {
  const SessionCreateRequest({
    required this.projectPath,
    required this.firstPrompt,
    required this.model,
  });

  final String projectPath;
  final String firstPrompt;
  final String model;
}

class AleraSession {
  const AleraSession({
    required this.id,
    required this.request,
    required this.workspacePath,
    required this.createdAt,
    required this.updatedAt,
    required this.title,
    required this.model,
    this.threadId,
    this.lastTurnId,
  });

  final String id;
  final SessionCreateRequest request;
  final String workspacePath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String title;
  final String model;
  final String? threadId;
  final String? lastTurnId;

  AleraSession copyWith({
    String? threadId,
    String? workspacePath,
    String? lastTurnId,
    DateTime? updatedAt,
    String? title,
    String? model,
  }) {
    return AleraSession(
      id: id,
      request: request,
      workspacePath: workspacePath ?? this.workspacePath,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      title: title ?? this.title,
      model: model ?? this.model,
      threadId: threadId ?? this.threadId,
      lastTurnId: lastTurnId ?? this.lastTurnId,
    );
  }
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  return null;
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.map((item) => item.toString()).toList(growable: false);
}

Map<String, String>? _stringMap(Object? value) {
  if (value == null) {
    return null;
  }
  final map = _asMap(value);
  if (map == null) {
    return null;
  }
  return map.map<String, String>(
    (key, mapValue) => MapEntry(key, mapValue.toString()),
  );
}

List<T> _mapList<T>(
  Object? value,
  T Function(Map<String, dynamic> json) fromJson,
) {
  if (value is! List) {
    return List<T>.empty(growable: false);
  }
  return value
      .whereType<Map>()
      .map((item) => fromJson(item.cast<String, dynamic>()))
      .toList(growable: false);
}
