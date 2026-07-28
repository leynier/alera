final class BrowserTrustedCertificate {
  const BrowserTrustedCertificate({
    required this.profileId,
    required this.host,
    required this.fingerprintSha256,
    required this.createdAt,
    required this.lastUsedAt,
    this.subject,
    this.issuer,
    this.validFrom,
    this.validTo,
  });

  factory BrowserTrustedCertificate.fromJson(Map<String, Object?> json) {
    final profileId = json['profileId'];
    final host = json['host'];
    final fingerprint = json['fingerprintSha256'];
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final lastUsedAt = DateTime.tryParse(json['lastUsedAt'] as String? ?? '');
    if (profileId is! String ||
        profileId.isEmpty ||
        host is! String ||
        host.isEmpty ||
        fingerprint is! String ||
        fingerprint.length != 64 ||
        createdAt == null ||
        lastUsedAt == null) {
      throw const FormatException('Browser Trusted Certificate Is Invalid.');
    }
    return BrowserTrustedCertificate(
      profileId: profileId,
      host: host,
      fingerprintSha256: fingerprint,
      subject: json['subject'] as String?,
      issuer: json['issuer'] as String?,
      validFrom: DateTime.tryParse(json['validFrom'] as String? ?? '')?.toUtc(),
      validTo: DateTime.tryParse(json['validTo'] as String? ?? '')?.toUtc(),
      createdAt: createdAt.toUtc(),
      lastUsedAt: lastUsedAt.toUtc(),
    );
  }

  final String profileId;
  final String host;
  final String fingerprintSha256;
  final String? subject;
  final String? issuer;
  final DateTime? validFrom;
  final DateTime? validTo;
  final DateTime createdAt;
  final DateTime lastUsedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'profileId': profileId,
    'host': host,
    'fingerprintSha256': fingerprintSha256,
    if (subject != null) 'subject': subject,
    if (issuer != null) 'issuer': issuer,
    if (validFrom != null) 'validFrom': validFrom!.toUtc().toIso8601String(),
    if (validTo != null) 'validTo': validTo!.toUtc().toIso8601String(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'lastUsedAt': lastUsedAt.toUtc().toIso8601String(),
  };
}

String normalizeBrowserCertificateHost(String value) {
  var host = value.trim().toLowerCase();
  if (host.startsWith('[') && host.endsWith(']')) {
    host = host.substring(1, host.length - 1);
  }
  return host.endsWith('.') ? host.substring(0, host.length - 1) : host;
}

String normalizeBrowserCertificateFingerprint(String value) =>
    value.replaceAll(':', '').trim().toLowerCase();

String displayBrowserCertificateFingerprint(String value) {
  final normalized = normalizeBrowserCertificateFingerprint(value);
  return <String>[
    for (var index = 0; index < normalized.length; index += 2)
      normalized.substring(index, index + 2).toUpperCase(),
  ].join(':');
}
