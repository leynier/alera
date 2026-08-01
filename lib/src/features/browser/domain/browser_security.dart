enum BrowserSecurityLevel {
  unknown,
  secure,
  insecure,
  local,
  certificateFailure,
}

final class BrowserCertificateChallenge {
  const BrowserCertificateChallenge({
    required this.id,
    required this.host,
    required this.port,
    required this.errorCode,
    required this.expiresAt,
    this.fingerprint,
    this.canProceed = false,
  });

  factory BrowserCertificateChallenge.fromJson(Map<String, Object?> json) {
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

  final String id;
  final String host;
  final int port;
  final String errorCode;
  final String? fingerprint;
  final DateTime expiresAt;
  final bool canProceed;

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

final class BrowserSecurityState {
  const BrowserSecurityState({
    this.level = BrowserSecurityLevel.unknown,
    this.origin,
    this.challenge,
  });

  factory BrowserSecurityState.fromJson(Map<String, Object?> json) {
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

  final BrowserSecurityLevel level;
  final String? origin;
  final BrowserCertificateChallenge? challenge;

  bool get isSecure =>
      level == BrowserSecurityLevel.secure ||
      level == BrowserSecurityLevel.local;

  Map<String, Object?> toJson() => <String, Object?>{
    'level': level.name,
    if (origin != null) 'origin': origin,
    if (challenge != null) 'challenge': challenge!.toJson(),
  };
}

final class BrowserTlsRequest {
  const BrowserTlsRequest({
    required this.pageId,
    required this.requestedAt,
    required this.host,
    required this.fingerprintSha256,
    this.url,
    this.description,
    this.subject,
    this.issuer,
    this.validFrom,
    this.validTo,
    this.errors = const <BrowserTlsErrorType>{},
  });

  final String pageId;
  final String host;
  final String fingerprintSha256;
  final Uri? url;
  final String? description;
  final String? subject;
  final String? issuer;
  final DateTime? validFrom;
  final DateTime? validTo;
  final Set<BrowserTlsErrorType> errors;
  final DateTime requestedAt;
}

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
