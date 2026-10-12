import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/runtime_request_error.dart';

/// Settles a pending request with the runtime's response: its payload, or a
/// [RuntimeRequestError] carrying the runtime's text and its additive
/// `errorCode`.
void completeRuntimeResponse(
  Completer<Object?> completer,
  Map<String, Object?> message,
) {
  if (message['ok'] == true) {
    completer.complete(message['payload']);
    return;
  }
  final code = message['errorCode'];
  completer.completeError(
    RuntimeRequestError(
      (message['error'] as String?) ?? 'Mobile runtime error.',
      code: code is String && code.isNotEmpty ? code : null,
    ),
  );
}
