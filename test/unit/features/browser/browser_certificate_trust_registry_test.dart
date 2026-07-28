import 'package:alera/src/features/browser/application/browser_certificate_trust_service.dart';
import 'package:alera/src/features/browser/domain/browser_trusted_certificate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matches session trust by exact profile host and fingerprint', () async {
    final service = _FakeCertificateTrustService();
    final registry = BrowserCertificateTrustRegistry(service);
    registry.trustForSession(
      profileId: 'work',
      host: '[LOCALHOST.]',
      fingerprintSha256: _fingerprintA.toUpperCase(),
    );

    expect(
      await registry.isTrusted(
        profileId: 'work',
        host: 'localhost',
        fingerprintSha256: _fingerprintA,
      ),
      isTrue,
    );
    expect(
      await registry.isTrusted(
        profileId: 'personal',
        host: 'localhost',
        fingerprintSha256: _fingerprintA,
      ),
      isFalse,
    );
    expect(
      await registry.isTrusted(
        profileId: 'work',
        host: 'localhost',
        fingerprintSha256: _fingerprintB,
      ),
      isFalse,
    );
  });

  test('persistent trust is saved before entering session cache', () async {
    final service = _FakeCertificateTrustService();
    final registry = BrowserCertificateTrustRegistry(service);
    final certificate = _certificate(_fingerprintA);

    await registry.trustPermanently(certificate);

    expect(service.saved, <BrowserTrustedCertificate>[certificate]);
    expect(
      await registry.isTrusted(
        profileId: 'work',
        host: 'service.local',
        fingerprintSha256: _fingerprintA,
      ),
      isTrue,
    );
  });

  test('display fingerprint is colon separated uppercase bytes', () {
    expect(
      displayBrowserCertificateFingerprint(_fingerprintA),
      'AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:'
      'AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA',
    );
  });

  test('trusted certificate payload round-trips and rejects invalid data', () {
    final createdAt = DateTime.utc(2026, 7, 28);
    final certificate = BrowserTrustedCertificate(
      profileId: 'work',
      host: 'service.local',
      fingerprintSha256: _fingerprintA,
      subject: 'Local Service',
      issuer: 'Development CA',
      validFrom: createdAt.subtract(const Duration(minutes: 1)),
      validTo: createdAt.add(const Duration(days: 30)),
      createdAt: createdAt,
      lastUsedAt: createdAt,
    );

    final decoded = BrowserTrustedCertificate.fromJson(certificate.toJson());

    expect(decoded.profileId, certificate.profileId);
    expect(decoded.host, certificate.host);
    expect(decoded.fingerprintSha256, certificate.fingerprintSha256);
    expect(decoded.subject, certificate.subject);
    expect(decoded.issuer, certificate.issuer);
    expect(decoded.validFrom, certificate.validFrom);
    expect(decoded.validTo, certificate.validTo);
    expect(decoded.createdAt, certificate.createdAt);
    expect(decoded.lastUsedAt, certificate.lastUsedAt);
    expect(
      () => BrowserTrustedCertificate.fromJson(<String, Object?>{
        ...certificate.toJson(),
        'fingerprintSha256': 'short',
      }),
      throwsFormatException,
    );
  });
}

const String _fingerprintA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _fingerprintB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

BrowserTrustedCertificate _certificate(String fingerprint) {
  final now = DateTime.utc(2026, 7, 28);
  return BrowserTrustedCertificate(
    profileId: 'work',
    host: 'service.local',
    fingerprintSha256: fingerprint,
    createdAt: now,
    lastUsedAt: now,
  );
}

final class _FakeCertificateTrustService
    implements BrowserCertificateTrustService {
  final List<BrowserTrustedCertificate> saved = <BrowserTrustedCertificate>[];

  @override
  Future<List<BrowserTrustedCertificate>> list({String? profileId}) async {
    return <BrowserTrustedCertificate>[
      for (final certificate in saved)
        if (profileId == null || certificate.profileId == profileId)
          certificate,
    ];
  }

  @override
  Future<bool> remove(BrowserTrustedCertificate certificate) async {
    return saved.remove(certificate);
  }

  @override
  Future<BrowserTrustedCertificate> trust(
    BrowserTrustedCertificate certificate,
  ) async {
    saved.add(certificate);
    return certificate;
  }
}
