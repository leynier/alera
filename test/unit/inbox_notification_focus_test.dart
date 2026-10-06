import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/agent_status/application/agent_status_notification_activation_service.dart';
import 'package:alera/src/features/agent_status/application/agent_status_notifications.dart';
import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:alera/src/features/inbox/application/inbox_navigation.dart';
import 'package:alera/src/features/inbox/application/inbox_notifications.dart';
import 'package:alera/src/features/inbox/application/inbox_providers.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/inbox_test_client.dart';

class _WindowFocus implements AppForeground {
  _WindowFocus(this._focused);

  bool _focused;
  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  set focused(bool value) {
    _focused = value;
    _changes.add(value);
  }

  @override
  bool get isForeground => _focused;

  @override
  Stream<bool> get changes => _changes.stream;

  @override
  void dispose() => unawaited(_changes.close());
}

class _Presenter implements AgentStatusNotificationPresenter {
  final List<AgentStatusNotification> shown = <AgentStatusNotification>[];

  @override
  Future<void> initialize({
    required AgentStatusNotificationSelectionHandler onSelected,
  }) async {}

  @override
  Future<void> show(AgentStatusNotification notification) async =>
      shown.add(notification);
}

class _Activator implements AgentNotificationWindowActivator {
  @override
  Future<void> showAndFocus() async {}
}

void main() {
  test(
    'a reply notifies while the inbox is open in an unfocused window',
    () async {
      var unread = 1;
      final client = InboxTestClient();
      client.handlers['inbox.summary'] = (_) => <String, Object?>{
        'items': [
          {'inbox': 'ext:user', 'unreadReplyCount': unread},
        ],
      };
      final focus = _WindowFocus(false);
      final presenter = _Presenter();
      final container = ProviderContainer(
        overrides: [
          ...inboxClientOverrides(client),
          inboxWindowFocusProvider.overrideWithValue(focus),
          agentStatusNotificationPresenterProvider.overrideWithValue(presenter),
          agentStatusNotificationWindowActivatorProvider.overrideWithValue(
            _Activator(),
          ),
          settingsControllerProvider.overrideWithValue(
            AleraSettings.defaults.copyWith(
              agents: AleraSettings.defaults.agents.copyWith(
                agentStatusNotificationsEnabled: true,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(client.events.close);
      container.read(inboxNavigationProvider.notifier).open();
      // The shell watches it; a provider nobody listens to is paused.
      container.listen(inboxReplyNotificationCoordinatorProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 30));

      unread = 2;
      client.emit('inboxChanged');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(presenter.shown, hasLength(1));

      focus.focused = true;
      unread = 3;
      client.emit('inboxChanged');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(presenter.shown, hasLength(1));
    },
  );
}
