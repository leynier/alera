import 'dart:convert';

import 'package:alera/src/features/agent_status/domain/agent_status.dart';

const int agentHookRequestMaxBytes = 1000 * 1000;

Object? decodeAgentHookRequestBody({
  required String contentType,
  required List<int> bodyBytes,
}) {
  if (bodyBytes.length > agentHookRequestMaxBytes) {
    throw const FormatException('Agent hook request body is too large.');
  }
  final body = utf8.decode(bodyBytes, allowMalformed: true);
  if (body.trim().isEmpty) {
    return <String, Object?>{};
  }
  if (contentType.contains('application/x-www-form-urlencoded')) {
    return Uri.splitQueryString(body, encoding: utf8);
  }
  return jsonDecode(body);
}

AgentHookEvent? parseAgentHookRequest({
  required AgentType agentType,
  required Object? body,
}) {
  if (body is! Map) {
    return null;
  }
  final record = Map<String, Object?>.from(body);
  final terminalSessionId = _requiredString(record['terminalSessionId']);
  final workspaceId = _requiredString(record['workspaceId']);
  final tabId = _requiredString(record['tabId']);
  final rawPayload = record['payload'];
  final payload = _payloadMap(rawPayload);
  if (terminalSessionId == null ||
      workspaceId == null ||
      tabId == null ||
      payload == null) {
    return null;
  }
  return AgentHookEvent(
    terminalSessionId: terminalSessionId,
    workspaceId: workspaceId,
    tabId: tabId,
    agentType: agentType,
    payload: payload,
    hookEventName:
        _optionalString(record['hookEventName']) ??
        _optionalString(record['hook_event_name']),
    version: _optionalString(record['version']),
  );
}

String? _requiredString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _optionalString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Map<String, Object?>? _payloadMap(Object? value) {
  if (value is String) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return Map<String, Object?>.from(decoded);
      }
    } catch (_) {
      return null;
    }
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  return null;
}
