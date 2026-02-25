sealed class SessionRuntimeEvent {
  const SessionRuntimeEvent();
}

class SessionNotificationEvent extends SessionRuntimeEvent {
  const SessionNotificationEvent({required this.method, required this.payload});

  final String method;
  final Map<String, dynamic> payload;
}

class SessionApprovalRequestEvent extends SessionRuntimeEvent {
  const SessionApprovalRequestEvent({
    required this.requestId,
    required this.method,
    required this.description,
    this.threadId,
  });

  final Object requestId;
  final String method;
  final String description;
  final String? threadId;
}

class SessionUserInputRequestEvent extends SessionRuntimeEvent {
  const SessionUserInputRequestEvent({
    required this.requestId,
    required this.threadId,
    required this.turnId,
    required this.itemId,
    required this.questions,
  });

  final Object requestId;
  final String? threadId;
  final String turnId;
  final String itemId;
  final List<Map<String, dynamic>> questions;
}
