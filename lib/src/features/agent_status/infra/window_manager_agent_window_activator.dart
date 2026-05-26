import 'package:alera/src/features/agent_status/application/agent_status_notification_activation_service.dart';
import 'package:window_manager/window_manager.dart';

class WindowManagerAgentWindowActivator
    implements AgentNotificationWindowActivator {
  const WindowManagerAgentWindowActivator();

  @override
  Future<void> showAndFocus() async {
    await windowManager.show();
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.focus();
  }
}
