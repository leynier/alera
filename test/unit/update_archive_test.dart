import 'dart:convert';

import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/updater/infra/update_archive.dart';
import 'package:alera/src/features/updater/infra/update_manifest_signature.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AleraUpdateArchive', () {
    test('selects the preferred installer for the latest platform build', () {
      final archive = AleraUpdateArchive.fromJsonString('''
{
  "schemaVersion": 2,
  "items": [
    {
      "version": "1.2.3",
      "shortVersion": 12,
      "date": "2026-07-27",
      "mandatory": false,
      "changes": [],
      "platform": "linux",
      "installerKind": "deb",
      "url": "https://example.com/alera.deb",
      "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "size": 10
    },
    {
      "version": "1.2.3",
      "shortVersion": 12,
      "date": "2026-07-27",
      "mandatory": false,
      "changes": [],
      "platform": "linux",
      "installerKind": "rpm",
      "url": "https://example.com/alera.rpm",
      "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "size": 11
    }
  ]
}
''');

      expect(
        archive
            .latestFor(
              platform: 'linux',
              currentBuildNumber: 1,
              channel: AleraUpdateChannel.stable,
              preferredInstallerKinds: const <String>['rpm'],
            )
            ?.installerKind,
        'rpm',
      );
      expect(
        archive.latestFor(
          platform: 'linux',
          currentBuildNumber: 1,
          channel: AleraUpdateChannel.stable,
          preferredInstallerKinds: const <String>[],
        ),
        isNull,
      );
    });

    test('selects latest stable update for the current platform', () {
      final archive = AleraUpdateArchive.fromJsonString(_archiveJson);

      final latest = archive.latestFor(
        platform: 'macos',
        currentBuildNumber: 1,
        channel: AleraUpdateChannel.stable,
      );

      expect(latest?.version, '0.1.2');
      expect(latest?.shortVersion, 3);
      expect(latest?.platform, 'macos');
    });

    test('ignores release candidates on the stable channel', () {
      final archive = AleraUpdateArchive.fromJsonString(_archiveJson);

      final latest = archive.latestFor(
        platform: 'windows',
        currentBuildNumber: 1,
        channel: AleraUpdateChannel.stable,
      );

      expect(latest, isNull);
    });

    test('includes release candidates on the rc channel', () {
      final archive = AleraUpdateArchive.fromJsonString(_archiveJson);

      final latest = archive.latestFor(
        platform: 'windows',
        currentBuildNumber: 1,
        channel: AleraUpdateChannel.rc,
      );

      expect(latest?.version, '0.1.3-rc.0');
      expect(latest?.shortVersion, 4);
    });

    test('ignores same and older build numbers', () {
      final archive = AleraUpdateArchive.fromJsonString(_archiveJson);

      final latest = archive.latestFor(
        platform: 'linux',
        currentBuildNumber: 2,
        channel: AleraUpdateChannel.stable,
      );

      expect(latest, isNull);
    });

    test('parses numeric strings and rejects invalid required fields', () {
      final parsed = AleraUpdateArchive.fromJson(<String, Object?>{
        'items': <Object?>[
          <String, Object?>{
            'version': '1.0.0',
            'shortVersion': '5',
            'date': '2026-05-25',
            'mandatory': false,
            'url': 'https://example.com/updates/1.0.0',
            'platform': 'macos',
          },
        ],
      });

      expect(parsed.items.single.shortVersion, 5);

      expect(
        () => AleraUpdateArchive.fromJson(<String, Object?>{
          'items': <Object?>[
            <String, Object?>{
              'version': '   ',
              'shortVersion': 5,
              'date': '2026-05-25',
              'mandatory': false,
              'url': 'https://example.com/updates/1.0.0',
              'platform': 'macos',
            },
          ],
        }),
        throwsFormatException,
      );

      expect(
        () => AleraUpdateArchive.fromJson(<String, Object?>{
          'items': <Object?>[
            <String, Object?>{
              'version': '1.0.0',
              'shortVersion': 'oops',
              'date': '2026-05-25',
              'mandatory': false,
              'url': 'https://example.com/updates/1.0.0',
              'platform': 'macos',
            },
          ],
        }),
        throwsFormatException,
      );

      expect(
        () => AleraUpdateArchive.fromJson(<String, Object?>{
          'items': <Object?>[
            <String, Object?>{
              'version': '1.0.0',
              'shortVersion': 5,
              'date': '2026-05-25',
              'mandatory': 'yes',
              'url': 'https://example.com/updates/1.0.0',
              'platform': 'macos',
            },
          ],
        }),
        throwsFormatException,
      );
    });

    test('parses schema v2 items with integrity metadata', () {
      final archive = AleraUpdateArchive.fromJsonString(_archiveV2Json);

      final linux = archive.latestFor(
        platform: 'linux',
        currentBuildNumber: 1,
        channel: AleraUpdateChannel.stable,
      );

      expect(archive.schemaVersion, 2);
      expect(archive.items, hasLength(3));
      expect(linux?.installerKind, 'deb');
      expect(linux?.sha256, startsWith('aaaaaaaa'));
      expect(linux?.size, 42);
      expect(linux?.signatureBundleUrl, isNull);
      expect(linux?.provenanceUrl, isNull);
    });

    test('rejects malformed schema entries instead of dropping them', () {
      expect(
        () => AleraUpdateArchive.fromJson(<String, Object?>{
          'schemaVersion': 2,
          'items': <Object?>['not-an-object'],
        }),
        throwsFormatException,
      );

      expect(
        () => AleraUpdateArchive.fromJson(<String, Object?>{
          'schemaVersion': 2,
          'items': <Object?>[
            <String, Object?>{
              'version': '1.0.0',
              'shortVersion': 10,
              'changes': <Object?>[],
              'date': '2026-06-06',
              'mandatory': false,
              'artifacts': <Object?>['not-an-object'],
            },
          ],
        }),
        throwsFormatException,
      );
    });

    test('requires schema v2 integrity metadata', () {
      final missingSha = Map<String, Object?>.from(jsonDecode(_archiveV2Json));
      final missingShaItems = List<Object?>.from(missingSha['items'] as List);
      final missingShaItem = Map<String, Object?>.from(
        missingShaItems.first as Map,
      )..remove('sha256');
      missingShaItems[0] = missingShaItem;
      missingSha['items'] = missingShaItems;

      expect(
        () => AleraUpdateArchive.fromJson(missingSha),
        throwsFormatException,
      );

      final invalidSize = Map<String, Object?>.from(jsonDecode(_archiveV2Json));
      final invalidSizeItems = List<Object?>.from(invalidSize['items'] as List);
      final invalidSizeItem = Map<String, Object?>.from(
        invalidSizeItems.first as Map,
      )..['size'] = 0;
      invalidSizeItems[0] = invalidSizeItem;
      invalidSize['items'] = invalidSizeItems;

      expect(
        () => AleraUpdateArchive.fromJson(invalidSize),
        throwsFormatException,
      );

      final invalidSha = Map<String, Object?>.from(jsonDecode(_archiveV2Json));
      final invalidShaItems = List<Object?>.from(invalidSha['items'] as List);
      final invalidShaItem = Map<String, Object?>.from(
        invalidShaItems.first as Map,
      )..['sha256'] = 'not-a-sha';
      invalidShaItems[0] = invalidShaItem;
      invalidSha['items'] = invalidShaItems;

      expect(
        () => AleraUpdateArchive.fromJson(invalidSha),
        throwsFormatException,
      );
    });

    test('verifies signed schema v2 manifests', () async {
      final keyPair = await Ed25519().newKeyPairFromSeed(List.filled(32, 1));
      final keyData = await keyPair.extract();
      final publicKeyData = await keyPair.extractPublicKey();
      final privateKey = base64Encode(keyData.bytes);
      final publicKey = base64Encode(publicKeyData.bytes);
      final decoded = Map<String, Object?>.from(jsonDecode(_archiveV2Json));
      final signed = await signAleraManifest(
        manifest: decoded,
        privateKeyBase64: privateKey,
        publicKeyBase64: publicKey,
        publicKeyId: 'test-key',
      );

      final archive = await AleraUpdateArchive.fromSignedJsonString(
        jsonEncode(signed),
        publicKeyBase64: publicKey,
      );

      expect(archive.schemaVersion, 2);

      final tampered = Map<String, Object?>.from(signed)..['version'] = '9.9.9';
      await expectLater(
        AleraUpdateArchive.fromSignedJsonString(
          jsonEncode(tampered),
          publicKeyBase64: publicKey,
        ),
        throwsFormatException,
      );
    });

    test('rejects empty manifest public key ids when signing', () async {
      final keyPair = await Ed25519().newKeyPairFromSeed(List.filled(32, 1));
      final keyData = await keyPair.extract();
      final publicKeyData = await keyPair.extractPublicKey();
      final privateKey = base64Encode(keyData.bytes);
      final publicKey = base64Encode(publicKeyData.bytes);
      final decoded = Map<String, Object?>.from(jsonDecode(_archiveV2Json));

      await expectLater(
        signAleraManifest(
          manifest: decoded,
          privateKeyBase64: privateKey,
          publicKeyBase64: publicKey,
          publicKeyId: '   ',
        ),
        throwsFormatException,
      );
    });
  });
}

const String _archiveJson = '''
{
  "appName": "Alera",
  "description": "Alera desktop agentic development environment.",
  "items": [
    {
      "version": "0.1.1",
      "shortVersion": 2,
      "changes": [{"type": "fix", "message": "Fix one."}],
      "date": "2026-05-24",
      "mandatory": false,
      "url": "https://example.com/updates/0.1.1+2-macos",
      "platform": "macos"
    },
    {
      "version": "0.1.2",
      "shortVersion": 3,
      "changes": [{"type": "fix", "message": "Fix two."}],
      "date": "2026-05-24",
      "mandatory": false,
      "url": "https://example.com/updates/0.1.2+3-macos",
      "platform": "macos"
    },
    {
      "version": "0.1.3-rc.0",
      "shortVersion": 4,
      "changes": [{"type": "feat", "message": "Preview."}],
      "date": "2026-05-24",
      "mandatory": false,
      "url": "https://example.com/updates/0.1.3+4-windows",
      "platform": "windows"
    },
    {
      "version": "0.1.1",
      "shortVersion": 2,
      "changes": [{"type": "fix", "message": "Linux fix."}],
      "date": "2026-05-24",
      "mandatory": false,
      "url": "https://example.com/updates/0.1.1+2-linux",
      "platform": "linux"
    }
  ]
}
''';

const String _archiveV2Json = '''
{
  "schemaVersion": 2,
  "appName": "Alera",
  "description": "Alera desktop agentic development environment.",
  "channel": "stable",
  "version": "1.0.0",
  "buildNumber": 10,
  "publishedAt": "2026-06-06T00:00:00Z",
  "items": [
    {
      "version": "1.0.0",
      "shortVersion": 10,
      "changes": [{"type": "fix", "message": "Fix release."}],
      "date": "2026-06-06",
      "mandatory": false,
      "platform": "macos",
      "installerKind": "tar.gz",
      "url": "https://example.com/alera-macos.tar.gz",
      "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "size": 40
    },
    {
      "version": "1.0.0",
      "shortVersion": 10,
      "changes": [{"type": "fix", "message": "Fix release."}],
      "date": "2026-06-06",
      "mandatory": false,
      "platform": "linux",
      "installerKind": "deb",
      "url": "https://example.com/alera.deb",
      "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "size": 42
    },
    {
      "version": "1.0.0",
      "shortVersion": 10,
      "changes": [{"type": "fix", "message": "Fix release."}],
      "date": "2026-06-06",
      "mandatory": false,
      "platform": "linux",
      "installerKind": "rpm",
      "url": "https://example.com/alera.rpm",
      "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "size": 43
    }
  ]
}
''';
