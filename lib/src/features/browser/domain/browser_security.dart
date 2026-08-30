enum BrowserSecurityLevel {
  unknown,
  secure,
  insecure,
  local,
  certificateFailure,
}

final class const BrowserCertificateChallenge({
  required final String id,
  required final String host,
  required final int port,
  required final String errorCode,
  required final DateTime expiresAt,
  final String? fingerprint,
  final bool canProceed = false,
}) {
  factory fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final host = json['host'];
    final port = json['port'];
    final errorCode = json['errorCode'];
    final expiresAt = DateTime.tryParse(json['expiresAt'] as String? ?? '');
    if (id is! String ||
        host is! String ||
        port is! num ||
        errorCode is! String ||
        expiresAt == null) {
      throw const FormatException('Browser certificate challenge is invalid.');
    }
    return BrowserCertificateChallenge(
      id: id,
      host: host,
      port: port.toInt(),
      errorCode: errorCode,
      expiresAt: expiresAt.toUtc(),
      fingerprint: json['fingerprint'] as String?,
      canProceed: json['canProceed'] == true,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'host': host,
    'port': port,
    'errorCode': errorCode,
    if (fingerprint != null) 'fingerprint': fingerprint,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'canProceed': canProceed,
  };
}

final class const BrowserSecurityState({
  final BrowserSecurityLevel level = BrowserSecurityLevel.unknown,
  final String? origin,
  final BrowserCertificateChallenge? challenge,
}) {
  factory fromJson(Map<String, Object?> json) {
    final challenge = json['challenge'];
    return BrowserSecurityState(
      level: BrowserSecurityLevel.values.firstWhere(
        (level) => level.name == json['level'],
        orElse: () => BrowserSecurityLevel.unknown,
      ),
      origin: json['origin'] as String?,
      challenge: challenge is Map
          ? BrowserCertificateChallenge.fromJson(
              Map<String, Object?>.from(challenge),
            )
          : null,
    );
  }

  static const unknown = BrowserSecurityState();

  bool get isSecure =>
      level == BrowserSecurityLevel.secure ||
      level == BrowserSecurityLevel.local;

  Map<String, Object?> toJson() => <String, Object?>{
    'level': level.name,
    if (origin != null) 'origin': origin,
    if (challenge != null) 'challenge': challenge!.toJson(),
  };
}

final class const BrowserTlsRequest({
  required final String pageId,
  required final DateTime requestedAt,
  required final String host,
  required final String fingerprintSha256,
  final Uri? url,
  final String? description,
  final String? subject,
  final String? issuer,
  final DateTime? validFrom,
  final DateTime? validTo,
  final Set<BrowserTlsErrorType> errors = const <BrowserTlsErrorType>{},
});

enum BrowserTlsErrorType {
  untrustedIssuer,
  nameMismatch,
  expired,
  notYetValid,
  revoked,
  insecure,
  other,
}

BrowserSecurityState browserSecurityForUrl(Uri url, {required bool committed}) {
  final origin = browserOrigin(url);
  if (!committed || origin == null) {
    return BrowserSecurityState(origin: origin);
  }
  final local = _isLocalBrowserHost(url.host);
  return BrowserSecurityState(
    level: local
        ? BrowserSecurityLevel.local
        : url.scheme == 'https'
        ? BrowserSecurityLevel.secure
        : BrowserSecurityLevel.insecure,
    origin: origin,
  );
}

String? browserOrigin(Uri url) {
  if ((url.scheme != 'http' && url.scheme != 'https') || url.host.isEmpty) {
    return null;
  }
  return url.origin;
}

bool _isLocalBrowserHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'localhost' ||
      normalized.endsWith('.localhost') ||
      normalized == '::1' ||
      normalized == '0.0.0.0' ||
      RegExp(r'^127(?:\.\d{1,3}){3}$').hasMatch(normalized);
}
