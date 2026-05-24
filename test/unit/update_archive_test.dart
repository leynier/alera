import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/updater/infra/update_archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AleraUpdateArchive', () {
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
