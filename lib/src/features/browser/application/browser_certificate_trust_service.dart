import 'package:alera/src/features/browser/domain/browser_trusted_certificate.dart';

abstract interface class BrowserCertificateTrustService {
  Future<List<BrowserTrustedCertificate>> list({String? profileId});

  Future<BrowserTrustedCertificate> trust(
    BrowserTrustedCertificate certificate,
  );

  Future<bool> remove(BrowserTrustedCertificate certificate);
}

final class BrowserCertificateTrustRegistry {
  BrowserCertificateTrustRegistry(this._service);

  final BrowserCertificateTrustService _service;
  final Set<String> _sessionTrust = <String>{};
  List<BrowserTrustedCertificate>? _persistentTrust;

  Future<bool> isTrusted({
    required String profileId,
    required String host,
    required String fingerprintSha256,
  }) async {
    final key = _key(profileId, host, fingerprintSha256);
    if (_sessionTrust.contains(key)) {
      return true;
    }
    final persistent = _persistentTrust ??= await _service.list();
    if (persistent.any(
      (certificate) =>
          _key(
            certificate.profileId,
            certificate.host,
            certificate.fingerprintSha256,
          ) ==
          key,
    )) {
      _sessionTrust.add(key);
      return true;
    }
    return false;
  }

  void trustForSession({
    required String profileId,
    required String host,
    required String fingerprintSha256,
  }) {
    _sessionTrust.add(_key(profileId, host, fingerprintSha256));
  }

  Future<BrowserTrustedCertificate> trustPermanently(
    BrowserTrustedCertificate certificate,
  ) async {
    final trusted = await _service.trust(certificate);
    _persistentTrust = <BrowserTrustedCertificate>[
      for (final existing in _persistentTrust ?? await _service.list())
        if (_key(
              existing.profileId,
              existing.host,
              existing.fingerprintSha256,
            ) !=
            _key(trusted.profileId, trusted.host, trusted.fingerprintSha256))
          existing,
      trusted,
    ];
    trustForSession(
      profileId: trusted.profileId,
      host: trusted.host,
      fingerprintSha256: trusted.fingerprintSha256,
    );
    return trusted;
  }

  void invalidatePersistentCache() {
    _persistentTrust = null;
  }
}

String _key(String profileId, String host, String fingerprintSha256) =>
    '$profileId\n${normalizeBrowserCertificateHost(host)}\n'
    '${normalizeBrowserCertificateFingerprint(fingerprintSha256)}';
