import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/terminal_host_settings_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('terminalHostConfigFor', () {
    test('the restore cap stays inside the retained scrollback', () {
      const settings = TerminalSettings.defaults;

      // 10 000 lines at 256 bytes each, well under the 10 MB the host keeps.
      expect(restoreSnapshotBytesFor(settings), 10000 * 256);

      // A tiny scrollback still restores enough to fill a viewport, and a
      // retention smaller than the floor caps the replay, never the other way.
      expect(
        restoreSnapshotBytesFor(settings.copyWith(scrollbackLines: 100)),
        256 * 1024,
      );
      expect(
        restoreSnapshotBytesFor(
          settings.copyWith(
            scrollbackLines: 100,
            hostScrollbackBytes: 64 * 1024,
          ),
        ),
        64 * 1024,
      );
      expect(
        restoreSnapshotBytesFor(
          settings.copyWith(hostScrollbackBytes: 1024 * 1024),
        ),
        1024 * 1024,
      );
    });

    test('carries the settings the host needs', () {
      final config = terminalHostConfigFor(
        TerminalSettings.defaults.copyWith(
          hostEmptyShutdownDelaySeconds: 7,
          hostDetachedSessionShutdownDelaySeconds: 14,
          hostScrollbackBytes: 4096,
        ),
      );

      expect(config.emptyShutdownDelaySeconds, 7);
      expect(config.detachedSessionShutdownDelaySeconds, 14);
      expect(config.scrollbackBytes, 4096);
      expect(config.restoreSnapshotBytes, 4096);
    });
  });
}
