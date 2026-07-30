import 'package:alera/src/features/updater/infra/linux_update_package.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Linux update package detection', () {
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
      expect(
        linuxInstallerKindFromOsRelease(
          'ID="opensuse-tumbleweed"\nID_LIKE="opensuse suse"\n',
        ),
        isNull,
        reason:
            'the published rpm requires Fedora package names that '
            'openSUSE does not provide, so no artifact is compatible there',
      );
    });
  });
}
