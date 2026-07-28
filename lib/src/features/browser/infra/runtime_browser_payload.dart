import 'package:alera/src/features/browser/domain/browser_error.dart';

Map<String, Object?> browserRuntimeSuccessMap(Object? payload, String label) {
  if (payload is! Map) {
    throw FormatException('$label must be a JSON object.');
  }
  final map = Map<String, Object?>.from(payload);
  if (map['ok'] != false) {
    return map;
  }
  final error = map['error'];
  if (error is! Map) {
    throw BrowserFailure(
      code: BrowserErrorCode.hostProtocol,
      message: '$label failed without a structured error.',
    );
  }
  final errorMap = Map<String, Object?>.from(error);
  final wireCode = errorMap['code'] as String?;
  throw BrowserFailure(
    code: _runtimeErrorCode(wireCode),
    message: errorMap['message'] as String? ?? '$label failed.',
    recoverable: true,
    details: <String, Object?>{
      'wireCode': ?wireCode,
      if (errorMap['nextSteps'] case final List<Object?> nextSteps)
        'nextSteps': <String>[
          for (final step in nextSteps)
            if (step is String) step,
        ],
    },
  );
}

List<Object?> browserRuntimeList(Map<String, Object?> payload, String key) {
  final items = payload[key];
  if (items is List) {
    return items;
  }
  throw FormatException('Browser runtime response must contain "$key".');
}

Map<String, Object?> browserRuntimeItem(Object? value, String label) {
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  throw FormatException('$label must be a JSON object.');
}

BrowserErrorCode _runtimeErrorCode(String? value) {
  return switch (value) {
    'page_not_found' || 'page_unavailable' => BrowserErrorCode.pageNotFound,
    'profile_not_found' => BrowserErrorCode.profileNotFound,
    'invalid_url' => BrowserErrorCode.invalidUrl,
    'navigation_blocked' => BrowserErrorCode.navigationBlocked,
    'engine_unavailable' => BrowserErrorCode.engineUnavailable,
    'unsupported_capability' => BrowserErrorCode.unsupportedCapability,
    'timeout' => BrowserErrorCode.timeout,
    _ => BrowserErrorCode.hostProtocol,
  };
}
