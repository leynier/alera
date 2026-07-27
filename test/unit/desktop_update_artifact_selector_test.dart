import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/updater/infra/desktop_update_artifact_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('desktop update artifact selection', () {
    test('uses tarballs for macOS, Windows, and Linux release candidates', () {
      expect(
        loadDesktopUpdateArtifactPreferences(
          'macos',
          AleraUpdateChannel.stable,
        ),
        completion(<String>['tar.gz']),
      );
      expect(
        loadDesktopUpdateArtifactPreferences(
          'windows',
          AleraUpdateChannel.stable,
        ),
        completion(<String>['tar.gz']),
      );
      expect(
        loadDesktopUpdateArtifactPreferences('linux', AleraUpdateChannel.rc),
        completion(<String>['tar.gz']),
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
