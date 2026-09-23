import 'package:alera/src/features/agent_status/infra/desktop_agent_status_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dev flavor uses a Windows toast identity distinct from release', () {
    expect(aleraWindowsNotificationAppUserModelId, 'Leynier.Alera.Dev');
    expect(
      aleraWindowsNotificationGuid,
      'd9d71450-17c3-41bd-b6ab-2e3fac3f417c',
    );
    expect(aleraWindowsNotificationAppUserModelId, isNot('Leynier.Alera'));
    expect(
      aleraWindowsNotificationGuid,
      isNot('6f03d61e-b22a-42fc-9e44-a02319d77f55'),
    );
  });
}
