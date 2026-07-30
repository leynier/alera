import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/updater/infra/desktop_updater_backend.dart';
import 'package:cryptography/cryptography.dart';
import 'package:desktop_updater/desktop_updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('DesktopUpdaterBackend', () {
    test('selects and verifies a signed schema 3 release', () async {
      final fixture = await _signedFixture();
      final backend = DesktopUpdaterBackend(client: _metadataClient(fixture));

      final candidate = await backend.checkForUpdate(
        archiveUrl: _archiveUrl,
        channel: 'stable',
        currentVersion: '1.0.0',
        currentBuildNumber: '1',
        platform: 'macos',
        requireSignature: true,
        publicKeyId: _publicKeyId,
        publicKeyBase64: fixture.publicKey,
      );

      expect(candidate?.version, '1.2.3');
      expect(candidate?.buildNumber, 2);
      expect(candidate?.platform, 'macos');
      expect(candidate?.artifactKind, 'zip');
      expect(candidate?.artifactUrl, _artifactUrl);
      expect(candidate?.artifactSha256, _sha256);
      expect(candidate?.artifactLength, 42);
    });

    test('rejects a descriptor signed by another key', () async {
      final fixture = await _signedFixture();
      final otherKeyPair = await Ed25519().newKeyPairFromSeed(
        List<int>.filled(32, 8),
      );
      final otherPublicKey = await otherKeyPair.extractPublicKey();
      final backend = DesktopUpdaterBackend(client: _metadataClient(fixture));

      await expectLater(
        backend.checkForUpdate(
          archiveUrl: _archiveUrl,
          channel: 'stable',
          currentVersion: '1.0.0',
          currentBuildNumber: '1',
          platform: 'macos',
          requireSignature: true,
          publicKeyId: _publicKeyId,
          publicKeyBase64: base64Encode(otherPublicKey.bytes),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('signature is invalid'),
          ),
        ),
      );
    });

    test('rejects descriptor identity drift from the index', () async {
      final fixture = await _signedFixture(descriptorPlatform: 'windows');
      final backend = DesktopUpdaterBackend(client: _metadataClient(fixture));

      await expectLater(
        backend.checkForUpdate(
          archiveUrl: _archiveUrl,
          channel: 'stable',
          currentVersion: '1.0.0',
          currentBuildNumber: '1',
          platform: 'macos',
          requireSignature: true,
          publicKeyId: _publicKeyId,
          publicKeyBase64: fixture.publicKey,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('does not match'),
          ),
        ),
      );
    });

    test('distinguishes a missing index from no newer release', () async {
      final missing = DesktopUpdaterBackend(
        client: MockClient((_) async => http.Response('', 404)),
      );
      final currentFixture = await _signedFixture();
      final current = DesktopUpdaterBackend(
        client: _metadataClient(currentFixture),
      );

      await expectLater(
        missing.checkForUpdate(
          archiveUrl: _archiveUrl,
          channel: 'stable',
          currentVersion: '1.0.0',
          currentBuildNumber: '1',
          platform: 'macos',
          requireSignature: false,
          publicKeyId: '',
          publicKeyBase64: '',
        ),
        throwsA(isA<DesktopUpdateIndexNotFound>()),
      );
      expect(
        await current.checkForUpdate(
          archiveUrl: _archiveUrl,
          channel: 'stable',
          currentVersion: '1.2.3',
          currentBuildNumber: '2',
          platform: 'macos',
          requireSignature: true,
          publicKeyId: _publicKeyId,
          publicKeyBase64: currentFixture.publicKey,
        ),
        isNull,
      );
    });

    test('reports non-success metadata responses', () async {
      final backend = DesktopUpdaterBackend(
        client: MockClient((_) async => http.Response('boom', 500)),
      );

      await expectLater(
        backend.checkForUpdate(
          archiveUrl: _archiveUrl,
          channel: 'stable',
          currentVersion: '1.0.0',
          currentBuildNumber: '1',
          platform: 'macos',
          requireSignature: false,
          publicKeyId: '',
          publicKeyBase64: '',
        ),
        throwsA(isA<HttpException>()),
      );
    });
  });
}

MockClient _metadataClient(_SignedFixture fixture) {
  return MockClient((request) async {
    if (request.url == _archiveUrl) {
      return http.Response(jsonEncode(fixture.index), 200);
    }
    if (request.url == _releaseUrl) {
      return http.Response(jsonEncode(fixture.descriptor), 200);
    }
    return http.Response('', 404);
  });
}

Future<_SignedFixture> _signedFixture({
  String descriptorPlatform = 'macos',
}) async {
  final keyPair = await Ed25519().newKeyPairFromSeed(List<int>.filled(32, 7));
  final publicKey = await keyPair.extractPublicKey();
  final unsigned = <String, dynamic>{
    'schemaVersion': 3,
    'packageId': 'dev.leynier.alera',
    'appName': 'Alera',
    'version': '1.2.3',
    'buildNumber': 2,
    'platform': descriptorPlatform,
    'channel': 'stable',
    'artifact': <String, dynamic>{
      'kind': 'zip',
      'url': _artifactUrl.toString(),
      'sha256': _sha256,
      'length': 42,
    },
    'install': <String, dynamic>{
      'strategy': descriptorPlatform == 'macos'
          ? 'wholeBundleReplace'
          : 'wholeDirectoryReplace',
    },
    'minimumUpdaterVersion': '2.5.0',
    'generatedAt': '2026-07-27T00:00:00.000Z',
    'signature': <String, dynamic>{
      'algorithm': 'ed25519',
      'publicKeyId': _publicKeyId,
      'value': '',
    },
  };
  final descriptor = ReleaseDescriptor.fromJson(unsigned);
  final signature = await Ed25519().sign(
    descriptor.canonicalSignatureBytes(),
    keyPair: keyPair,
  );
  final signed = descriptor.toJson();
  signed['signature'] = <String, dynamic>{
    'algorithm': 'ed25519',
    'publicKeyId': _publicKeyId,
    'value': base64Encode(signature.bytes),
  };
  return (
    index: <String, dynamic>{
      'schemaVersion': 3,
      'appName': 'Alera',
      'items': <Object?>[
        <String, dynamic>{
          'version': '1.2.3',
          'buildNumber': 2,
          'platform': 'macos',
          'channel': 'stable',
          'mandatory': false,
          'release': _releaseUrl.toString(),
        },
      ],
    },
    descriptor: signed,
    publicKey: base64Encode(publicKey.bytes),
  );
}

typedef _SignedFixture = ({
  Map<String, dynamic> index,
  Map<String, dynamic> descriptor,
  String publicKey,
});

final Uri _archiveUrl = Uri.parse(
  'https://updates.alera.build/updates/stable/app-archive.json',
);
final Uri _releaseUrl = Uri.parse(
  'https://updates.alera.build/updates/stable/releases/1.2.3/macos/release.json',
);
final Uri _artifactUrl = Uri.parse(
  'https://updates.alera.build/updates/stable/releases/1.2.3/macos/Alera-1.2.3-macos.zip',
);
const String _publicKeyId = 'test-key';
const String _sha256 =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
