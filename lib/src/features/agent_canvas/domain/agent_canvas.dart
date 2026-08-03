import 'package:dart_mappable/dart_mappable.dart';

part 'agent_canvas.mapper.dart';

@MappableEnum()
enum AgentCanvasState { waiting, live, completed, orphaned, closed }

extension AgentCanvasStateX on AgentCanvasState {
  bool get isHistory =>
      this == AgentCanvasState.completed ||
      this == AgentCanvasState.orphaned ||
      this == AgentCanvasState.closed;
}

@MappableEnum()
enum AgentCanvasDecisionState { pending, resolved, timeout }

@MappableClass()
class AgentCanvasDecision with AgentCanvasDecisionMappable {
  const AgentCanvasDecision({
    required this.id,
    required this.canvasId,
    required this.revision,
    required this.question,
    required this.options,
    required this.state,
    required this.createdAt,
    this.resolution,
    this.resolvedAt,
    this.expiresAt,
  });

  final String id;
  final String canvasId;
  final int revision;
  final String question;
  final Object? options;
  final AgentCanvasDecisionState state;
  final Object? resolution;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final DateTime? expiresAt;

  factory AgentCanvasDecision.fromJson(Map<String, Object?> json) =>
      AgentCanvasDecisionMapper.fromMap(Map<String, dynamic>.from(json));

  bool get isPending => state == AgentCanvasDecisionState.pending;
}

@MappableClass()
class AgentCanvas with AgentCanvasMappable {
  const AgentCanvas({
    required this.id,
    required this.workspaceId,
    required this.terminalSessionId,
    required this.agentType,
    required this.title,
    required this.state,
    required this.pinned,
    required this.frozen,
    required this.revision,
    required this.document,
    required this.decisions,
    required this.createdAt,
    required this.updatedAt,
    this.tabId,
    this.finalRevision,
    this.completedAt,
    this.expiresAt,
  });

  final String id;
  final String workspaceId;
  final String terminalSessionId;
  final String? tabId;
  final String agentType;
  final String title;
  final AgentCanvasState state;
  final bool pinned;
  final bool frozen;
  final int revision;
  final int? finalRevision;
  final Map<String, Object?> document;
  final List<AgentCanvasDecision> decisions;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final DateTime? expiresAt;

  factory AgentCanvas.fromJson(Map<String, Object?> json) =>
      AgentCanvasMapper.fromMap(Map<String, dynamic>.from(json));

  bool get isActive =>
      state == AgentCanvasState.waiting || state == AgentCanvasState.live;

  bool get hasPendingDecision =>
      decisions.any((decision) => decision.isPending);

  Object? get components => document['components'];
}

@MappableClass()
class AgentCanvasEvent with AgentCanvasEventMappable {
  const AgentCanvasEvent({
    required this.sequence,
    required this.canvasId,
    required this.workspaceId,
    required this.eventType,
    required this.payload,
    required this.createdAt,
  });

  final int sequence;
  final String canvasId;
  final String workspaceId;
  final String eventType;
  final Map<String, Object?> payload;
  final DateTime createdAt;

  factory AgentCanvasEvent.fromJson(Map<String, Object?> json) =>
      AgentCanvasEventMapper.fromMap(Map<String, dynamic>.from(json));
}
