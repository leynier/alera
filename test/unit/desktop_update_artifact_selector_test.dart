import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/updater/infra/desktop_update_artifact_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('desktop update artifact selection', () {
    test('uses tarballs only for macOS and Windows', () {
      expect(
        desktopUpdateArtifactPreferences(
          platform: 'macos',
          channel: AleraUpdateChannel.stable,
        ),
        <String>['tar.gz'],
      );
      expect(
        desktopUpdateArtifactPreferences(
          platform: 'windows',
          channel: AleraUpdateChannel.rc,
        ),
        <String>['tar.gz'],
      );
    });

    test('uses distribution packages for every Linux release channel', () {
      for (final channel in AleraUpdateChannel.values) {
        expect(
          desktopUpdateArtifactPreferences(
            platform: 'linux',
            channel: channel,
            linuxOsRelease: 'ID=ubuntu\nID_LIKE="debian"\n',
          ),
          <String>['deb'],
        );
        expect(
          desktopUpdateArtifactPreferences(
            platform: 'linux',
            channel: channel,
            linuxOsRelease: 'ID="rocky"\nID_LIKE="rhel fedora"\n',
          ),
          <String>['rpm'],
        );
      }
      expect(
        desktopUpdateArtifactPreferences(
          platform: 'linux',
          channel: AleraUpdateChannel.rc,
          linuxOsRelease: 'ID=arch\n',
        ),
        isEmpty,
      );
    });

    test('detects Debian and RPM distribution families', () {
      expect(
        linuxInstallerKindFromOsRelease('ID=ubuntu\nID_LIKE="debian"\n'),
        'deb',
      );
      expect(
        linuxInstallerKindFromOsRelease(
          'ID="rocky"\nID_LIKE="rhel centos fedora"\n',
        ),
        'rpm',
      );
      expect(linuxInstallerKindFromOsRelease('ID=arch\n'), isNull);
    });
  });
}
