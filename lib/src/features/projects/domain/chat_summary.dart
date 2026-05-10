class ChatSummary {
  const ChatSummary({
    required this.id,
    required this.projectId,
    this.worktreeId,
    required this.title,
    required this.model,
    this.threadId,
    this.lastTurnId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String projectId;
  final String? worktreeId;
  final String title;
  final String model;
  final String? threadId;
  final String? lastTurnId;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatSummary copyWith({
    String? title,
    String? model,
    String? threadId,
    String? lastTurnId,
    DateTime? updatedAt,
  }) {
    return ChatSummary(
      id: id,
      projectId: projectId,
      worktreeId: worktreeId,
      title: title ?? this.title,
      model: model ?? this.model,
      threadId: threadId ?? this.threadId,
      lastTurnId: lastTurnId ?? this.lastTurnId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'projectId': projectId,
      'worktreeId': worktreeId,
      'title': title,
      'model': model,
      'threadId': threadId,
      'lastTurnId': lastTurnId,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory ChatSummary.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final projectId = json['projectId'];
    final title = json['title'];
    final model = json['model'];
    final createdAt = json['createdAt'];
    final updatedAt = json['updatedAt'];
    if (id is! String || id.isEmpty) {
      throw StateError('Chat record missing id');
    }
    if (projectId is! String || projectId.isEmpty) {
      throw StateError('Chat record missing projectId');
    }
    if (title is! String) {
      throw StateError('Chat record missing title');
    }
    if (model is! String || model.isEmpty) {
      throw StateError('Chat record missing model');
    }
    if (createdAt is! String) {
      throw StateError('Chat record missing createdAt');
    }
    if (updatedAt is! String) {
      throw StateError('Chat record missing updatedAt');
    }
    final worktreeId = json['worktreeId'];
    final threadId = json['threadId'];
    final lastTurnId = json['lastTurnId'];
    return ChatSummary(
      id: id,
      projectId: projectId,
      worktreeId: worktreeId is String && worktreeId.isNotEmpty
          ? worktreeId
          : null,
      title: title,
      model: model,
      threadId: threadId is String && threadId.isNotEmpty ? threadId : null,
      lastTurnId: lastTurnId is String && lastTurnId.isNotEmpty
          ? lastTurnId
          : null,
      createdAt: DateTime.parse(createdAt).toUtc(),
      updatedAt: DateTime.parse(updatedAt).toUtc(),
    );
  }
}
