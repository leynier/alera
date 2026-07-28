import 'package:alera/src/features/browser/application/browser_certificate_trust_service.dart';
import 'package:alera/src/features/browser/domain/browser_trusted_certificate.dart';
import 'package:alera/src/features/browser/infra/runtime_browser_payload.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

final class RuntimeBrowserCertificateTrustService
    implements BrowserCertificateTrustService {
  const RuntimeBrowserCertificateTrustService(this._client);

  final RuntimeHostClient _client;

  @override
  Future<List<BrowserTrustedCertificate>> list({String? profileId}) async {
    final response = browserRuntimeSuccessMap(
      await _client.runtimeRequest(
        'browser.certificates.list',
        <String, Object?>{'profileId': ?profileId},
      ),
      'Browser certificate list',
    );
    return <BrowserTrustedCertificate>[
      for (final value in browserRuntimeList(response, 'certificates'))
        BrowserTrustedCertificate.fromJson(
          browserRuntimeItem(value, 'Browser trusted certificate'),
        ),
    ];
  }

  @override
  Future<BrowserTrustedCertificate> trust(
    BrowserTrustedCertificate certificate,
  ) async {
    final response = browserRuntimeSuccessMap(
      await _client.runtimeRequest(
        'browser.certificates.trust',
        certificate.toJson(),
      ),
      'Browser certificate trust',
    );
    return BrowserTrustedCertificate.fromJson(
      browserRuntimeItem(
        response['certificate'],
        'Browser trusted certificate',
      ),
    );
  }

  @override
  Future<bool> remove(BrowserTrustedCertificate certificate) async {
    final response = browserRuntimeSuccessMap(
      await _client
          .runtimeRequest('browser.certificates.remove', <String, Object?>{
            'profileId': certificate.profileId,
            'host': certificate.host,
            'fingerprintSha256': certificate.fingerprintSha256,
          }),
      'Browser certificate removal',
    );
    return response['removed'] == true;
  }
}
