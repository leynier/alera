import 'package:alera/src/shared/models/contracts.dart';

sealed class SessionRuntimeEvent {
  const SessionRuntimeEvent();
}

class SessionNotificationEvent extends SessionRuntimeEvent {
  const SessionNotificationEvent({required this.method, required this.payload});

  final String method;
  final Map<String, dynamic> payload;
}

class SessionApprovalRequestedEvent extends SessionRuntimeEvent {
  const SessionApprovalRequestedEvent(this.approval);

  final PendingApproval approval;
}
