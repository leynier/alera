enum BrowserErrorCode {
  engineUnavailable,
  unsupportedCapability,
  invalidUrl,
  navigationBlocked,
  pageNotFound,
  profileNotFound,
  staleAutomationReference,
  permissionDenied,
  certificateRejected,
  downloadFailed,
  invalidPayload,
  hostProtocol,
  operationInProgress,
  timeout,
  unknown,
}

final class const BrowserFailure({
  required final BrowserErrorCode code,
  required final String message,
  final bool recoverable = false,
  final Map<String, Object?> details = const <String, Object?>{},
}) implements Exception {
  factory fromJson(Map<String, Object?> json) {
    return BrowserFailure(
      code: BrowserErrorCode.values.firstWhere(
        (code) => code.name == json['code'],
        orElse: () => BrowserErrorCode.unknown,
      ),
      message: json['message'] is String
          ? json['message']! as String
          : 'Unknown browser error.',
      recoverable: json['recoverable'] == true,
      details: _browserErrorMap(json['details']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code.name,
    'message': message,
    'recoverable': recoverable,
    if (details.isNotEmpty) 'details': details,
  };

  @override
  String toString() => 'BrowserFailure(${code.name}): $message';
}

Map<String, Object?> _browserErrorMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.unmodifiable(value);
  }
  if (value is Map) {
    return Map<String, Object?>.unmodifiable(Map<String, Object?>.from(value));
  }
  return const <String, Object?>{};
}
