import 'package:alera_agent_chat/src/agent_chat_json.dart';

/// Provider-neutral item kinds. The runtime projects every provider's native
/// items into these; anything it cannot classify arrives as [unknown] and is
/// still rendered from its title and detail.
enum AgentChatItemType {
  userMessage,
  assistantMessage,
  reasoning,
  plan,
  commandExecution,
  fileChange,
  mcpToolCall,
  dynamicToolCall,
  collabAgentToolCall,
  webSearch,
  imageView,
  reviewEntered,
  reviewExited,
  contextCompaction,
  error,
  notice,
  unknown;

  static AgentChatItemType fromJson(Object? value) => agentChatWireEnum(
    value,
    AgentChatItemType.values,
    AgentChatItemType.unknown,
  );

  /// Work the agent did on the way to an answer, grouped under "Worked for".
  bool get isActivity => switch (this) {
    AgentChatItemType.commandExecution ||
    AgentChatItemType.fileChange ||
    AgentChatItemType.mcpToolCall ||
    AgentChatItemType.dynamicToolCall ||
    AgentChatItemType.collabAgentToolCall ||
    AgentChatItemType.webSearch ||
    AgentChatItemType.imageView ||
    AgentChatItemType.reviewEntered ||
    AgentChatItemType.reviewExited ||
    AgentChatItemType.unknown => true,
    _ => false,
  };
}

enum AgentChatItemStatus {
  inProgress,
  completed,
  failed,
  declined;

  static AgentChatItemStatus fromJson(Object? value) => agentChatWireEnum(
    value,
    AgentChatItemStatus.values,
    AgentChatItemStatus.completed,
  );
}

enum AgentChatAttachmentType(this.wire) {
  file('file'),
  localImage('localImage'),
  image('image');

  final String wire;

  static AgentChatAttachmentType fromJson(Object? value) =>
      switch (agentChatWireToken(value)) {
        'localimage' => AgentChatAttachmentType.localImage,
        'image' => AgentChatAttachmentType.image,
        _ => AgentChatAttachmentType.file,
      };

  bool get isImage => this != AgentChatAttachmentType.file;
}

/// A file or image sent with a user message. Paths are host paths; relative
/// paths resolve against the chat's working directory on the host.
class const AgentChatAttachment({
  required final AgentChatAttachmentType type,
  final String? path,
  final String? url,
  final String? name,
  final String? mimeType,
  final int? sizeBytes,
  final String? attachmentId,

  /// This device's explicit picked/pasted source. Never sent to the host.
  final String? localSourcePath,
}) {
  factory fromJson(Object? value, {bool localDraft = false}) {
    final json = agentChatJsonMap(value);
    return AgentChatAttachment(
      type: AgentChatAttachmentType.fromJson(json['type']),
      path: agentChatJsonString(json['path']),
      url: agentChatJsonString(json['url']),
      name: agentChatJsonString(json['name']),
      mimeType: agentChatJsonString(json['mimeType']),
      sizeBytes: agentChatJsonInt(json['sizeBytes']),
      attachmentId: agentChatJsonString(json['attachmentId']),
      localSourcePath: localDraft
          ? agentChatJsonString(json['localSourcePath'])
          : null,
    );
  }

  String get displayName {
    final explicit = name;
    if (explicit != null) return explicit;
    final source = path ?? url ?? '';
    final separator = source.lastIndexOf(RegExp(r'[\\/]'));
    final base = separator < 0 ? source : source.substring(separator + 1);
    return base.isEmpty ? 'Attachment' : base;
  }

  AgentChatJson toJson() => <String, Object?>{
    'type': type.wire,
    'path': ?path,
    'url': ?url,
    'name': ?name,
    'mimeType': ?mimeType,
    'sizeBytes': ?sizeBytes,
    'attachmentId': ?attachmentId,
  };
}

enum AgentChatFileChangeKind {
  add,
  delete,
  update,
  rename;

  static AgentChatFileChangeKind fromJson(Object? value) =>
      switch (agentChatWireToken(value)) {
        'add' ||
        'added' ||
        'create' ||
        'created' => AgentChatFileChangeKind.add,
        'delete' || 'deleted' || 'remove' => AgentChatFileChangeKind.delete,
        'rename' || 'renamed' || 'move' => AgentChatFileChangeKind.rename,
        _ => AgentChatFileChangeKind.update,
      };
}

class const AgentChatFileChange({
  required final String path,
  required final AgentChatFileChangeKind kind,
  final String? diff,
  final String? movePath,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatFileChange(
      path: agentChatJsonText(json['path']),
      kind: AgentChatFileChangeKind.fromJson(json['kind']),
      diff: agentChatJsonString(json['diff']),
      movePath: agentChatJsonString(json['movePath']),
    );
  }

  /// Added and removed line counts of [diff], ignoring the file headers.
  ({int additions, int deletions}) get lineCounts {
    var additions = 0;
    var deletions = 0;
    for (final line in (diff ?? '').split('\n')) {
      if (line.startsWith('+') && !line.startsWith('+++')) additions += 1;
      if (line.startsWith('-') && !line.startsWith('---')) deletions += 1;
    }
    return (additions: additions, deletions: deletions);
  }
}

enum AgentChatPlanStepStatus {
  pending,
  inProgress,
  completed;

  static AgentChatPlanStepStatus fromJson(Object? value) => agentChatWireEnum(
    value,
    AgentChatPlanStepStatus.values,
    AgentChatPlanStepStatus.pending,
  );
}

class const AgentChatPlanStep({
  required final String step,
  required final AgentChatPlanStepStatus status,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatPlanStep(
      step: agentChatJsonText(json['step']),
      status: AgentChatPlanStepStatus.fromJson(json['status']),
    );
  }
}

enum AgentChatItemOriginKind {
  user,
  chatMessage,
  orchestrationWake;

  static AgentChatItemOriginKind fromJson(Object? value) => agentChatWireEnum(
    value,
    AgentChatItemOriginKind.values,
    AgentChatItemOriginKind.user,
  );
}

/// Who put a user message into the chat when it was not the person: another
/// chat sending a message, or the runtime waking this chat because delegated
/// tasks finished. The runtime projects only these safe lineage fields.
class const AgentChatItemOrigin({
  required final AgentChatItemOriginKind kind,
  final String? senderChatId,
  final List<String> taskIds = const <String>[],
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatItemOrigin(
      kind: AgentChatItemOriginKind.fromJson(json['kind']),
      senderChatId: agentChatJsonString(json['senderChatId']),
      taskIds: agentChatJsonStringList(json['taskIds']),
    );
  }

  /// Whether an agent or the runtime, rather than a person, sent it.
  bool get automated => kind != AgentChatItemOriginKind.user;
}

enum AgentChatHandoffStatus {
  pending,
  completed,
  failed;

  static AgentChatHandoffStatus fromJson(Object? value) => agentChatWireEnum(
    value,
    AgentChatHandoffStatus.values,
    AgentChatHandoffStatus.pending,
  );
}

/// One side of a context handoff: the provider and model a session ran on.
class const AgentChatHandoffEndpoint({
  required final String provider,
  final String? providerInstanceId,
  final String? model,
}) {
  static AgentChatHandoffEndpoint? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = agentChatJsonMap(value);
    final provider = agentChatJsonString(json['provider']);
    if (provider == null) return null;
    return AgentChatHandoffEndpoint(
      provider: provider,
      providerInstanceId: agentChatJsonString(json['providerInstanceId']),
      model: agentChatJsonString(json['model']),
    );
  }
}

/// The transcript of earlier sessions reaching a fresh provider session with
/// a turn's prompt. The runtime records it as a `notice` whose `normalized`
/// carries `handoff`; [from] is null when no earlier turn names a source.
class const AgentChatHandoff({
  final AgentChatHandoffEndpoint? from,
  required final AgentChatHandoffEndpoint to,
  required final AgentChatHandoffStatus status,
}) {
  static AgentChatHandoff? fromItem(AgentChatItem item) {
    if (item.type != AgentChatItemType.notice) return null;
    final payload = item.normalized['handoff'];
    if (payload is! Map) return null;
    final json = agentChatJsonMap(payload);
    final to = AgentChatHandoffEndpoint.fromJson(json['to']);
    if (to == null) return null;
    return AgentChatHandoff(
      from: AgentChatHandoffEndpoint.fromJson(json['from']),
      to: to,
      status: item.isFailed
          ? AgentChatHandoffStatus.failed
          : AgentChatHandoffStatus.fromJson(json['status']),
    );
  }

  bool get failed => status == AgentChatHandoffStatus.failed;
}

/// One timeline row. Identity is [id], allocated by the runtime, so a stream
/// of updates rewrites one row instead of appending a row per notification.
class const AgentChatItem({
  required final String id,
  required final AgentChatItemType type,
  final String? wireType,
  required final AgentChatItemStatus status,
  required final DateTime createdAt,
  required final DateTime updatedAt,
  final String? turnId,
  final bool streaming = false,
  final String? title,
  final String? detail,
  final String text = '',
  final String reasoningText = '',
  final String output = '',
  final String? clientMessageId,
  final String? actor,
  final AgentChatItemOrigin? origin,
  final List<AgentChatAttachment> attachments = const <AgentChatAttachment>[],
  final String? command,
  final String? cwd,
  final int? exitCode,
  final int? durationMs,
  final List<AgentChatFileChange> changes = const <AgentChatFileChange>[],
  final String? toolName,
  final String? server,
  final Object? input,
  final Object? result,
  final String? query,
  final String? url,
  final String? imagePath,
  final List<AgentChatPlanStep> planSteps = const <AgentChatPlanStep>[],
  final String? explanation,
  final String? agentId,
  final String? parentItemId,
  final AgentChatJson normalized = const <String, Object?>{},
  final AgentChatJson data = const <String, Object?>{},

  /// The projection has only part of a segmented message. Render its loaded
  /// text literally because the missing prefix may contain Markdown syntax.
  final bool isPartialContinuation = false,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final id = agentChatJsonString(json['itemId'] ?? json['id']);
    if (id == null) {
      throw const FormatException('Agent chat item has no itemId.');
    }
    final normalized = agentChatJsonMap(json['normalized']);
    Object? field(String key) => normalized[key] ?? json[key];
    final createdAt =
        agentChatJsonDate(json['createdAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return AgentChatItem(
      id: id,
      turnId: agentChatJsonString(json['turnId']),
      type: AgentChatItemType.fromJson(json['type'] ?? json['itemType']),
      wireType: agentChatJsonString(json['type'] ?? json['itemType']),
      status: AgentChatItemStatus.fromJson(json['status']),
      streaming: agentChatJsonBool(json['streaming']),
      createdAt: createdAt,
      updatedAt: agentChatJsonDate(json['updatedAt']) ?? createdAt,
      title: agentChatJsonString(json['title']),
      detail: agentChatJsonString(json['detail']),
      text: agentChatJsonText(json['text']),
      reasoningText: agentChatJsonText(json['reasoningText']),
      output: agentChatJsonText(json['output']),
      clientMessageId: agentChatJsonString(json['clientMessageId']),
      actor: agentChatJsonString(json['actor']),
      origin: field('origin') is Map
          ? AgentChatItemOrigin.fromJson(field('origin'))
          : null,
      attachments: <AgentChatAttachment>[
        for (final item in agentChatJsonList(json['attachments']))
          AgentChatAttachment.fromJson(item),
      ],
      command: agentChatJsonString(field('command')),
      cwd: agentChatJsonString(field('cwd')),
      exitCode: agentChatJsonInt(field('exitCode')),
      durationMs: agentChatJsonInt(field('durationMs')),
      changes: <AgentChatFileChange>[
        for (final item in agentChatJsonList(field('changes')))
          AgentChatFileChange.fromJson(item),
      ],
      toolName: agentChatJsonString(field('toolName')),
      server: agentChatJsonString(field('server')),
      input: field('input'),
      result: field('result'),
      query: agentChatJsonString(field('query')),
      url: agentChatJsonString(field('url')),
      imagePath: agentChatJsonString(field('imagePath')),
      planSteps: <AgentChatPlanStep>[
        for (final item in agentChatJsonList(field('planSteps')))
          AgentChatPlanStep.fromJson(item),
      ],
      explanation: agentChatJsonString(field('explanation')),
      agentId: agentChatJsonString(field('agentId')),
      parentItemId: agentChatJsonString(field('parentItemId')),
      normalized: normalized,
      data: agentChatJsonMap(json['data']),
    );
  }

  /// The context handoff this notice marks, or null for any other item.
  AgentChatHandoff? get handoff => AgentChatHandoff.fromItem(this);

  /// A user message an agent or the runtime sent on this chat's behalf.
  bool get isAutomatedInput =>
      type == AgentChatItemType.userMessage && (origin?.automated ?? false);

  bool get isInProgress =>
      streaming || status == AgentChatItemStatus.inProgress;

  bool get isFailed =>
      status == AgentChatItemStatus.failed ||
      status == AgentChatItemStatus.declined;

  /// Whether a details panel has anything to show beyond the row label.
  bool get hasDetails =>
      (detail ?? '').trim().isNotEmpty ||
      output.trim().isNotEmpty ||
      command != null ||
      changes.isNotEmpty ||
      input != null ||
      result != null ||
      query != null ||
      url != null ||
      imagePath != null ||
      normalized['payloadRef'] is Map ||
      data.isNotEmpty;

  AgentChatItem copyWith({
    AgentChatItemStatus? status,
    DateTime? updatedAt,
    bool? streaming,
    String? text,
    String? reasoningText,
    String? output,
    bool? isPartialContinuation,
  }) => AgentChatItem(
    id: id,
    turnId: turnId,
    type: type,
    wireType: wireType,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    streaming: streaming ?? this.streaming,
    title: title,
    detail: detail,
    text: text ?? this.text,
    reasoningText: reasoningText ?? this.reasoningText,
    output: output ?? this.output,
    clientMessageId: clientMessageId,
    actor: actor,
    origin: origin,
    attachments: attachments,
    command: command,
    cwd: cwd,
    exitCode: exitCode,
    durationMs: durationMs,
    changes: changes,
    toolName: toolName,
    server: server,
    input: input,
    result: result,
    query: query,
    url: url,
    imagePath: imagePath,
    planSteps: planSteps,
    explanation: explanation,
    agentId: agentId,
    parentItemId: parentItemId,
    normalized: normalized,
    data: data,
    isPartialContinuation: isPartialContinuation ?? this.isPartialContinuation,
  );
}
