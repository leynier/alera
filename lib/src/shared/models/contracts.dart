enum AppServerConnectionState { disconnected, starting, connected, error }

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
