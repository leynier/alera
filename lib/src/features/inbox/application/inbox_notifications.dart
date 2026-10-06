import 'dart:async';
import 'dart:convert';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/agent_status/application/agent_status_notifications.dart';
import 'package:alera/src/features/inbox/application/inbox_navigation.dart';
import 'package:alera/src/features/inbox/application/inbox_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'inbox_notifications.g.dart';

const String _inboxNotificationKind = 'inboxReply';

// A single id, so a newer inbox notification replaces the previous one
// instead of stacking one per reply.
const int _inboxNotificationId = 0x494E4258;

/// Decides when a growing unread count deserves a system notification.
class InboxReplyNotificationTracker {
  int? _lastUnread;

  /// Returns how many replies are new, or 0. The first value seen is a
  /// baseline: replies already waiting when the app starts are not news.
  int observe(int unread, {required bool inboxVisible}) {
    final previous = _lastUnread;
    _lastUnread = unread;
    if (previous == null || inboxVisible || unread <= previous) return 0;
    return unread - previous;
  }
}

String encodeInboxNotificationPayload() =>
    jsonEncode(<String, String>{'kind': _inboxNotificationKind});

bool isInboxNotificationPayload(String payload) {
  try {
    final decoded = jsonDecode(payload);
    return decoded is Map && decoded['kind'] == _inboxNotificationKind;
  } on FormatException {
    return false;
  }
}

AgentStatusNotification inboxReplyNotification(
  int newReplies,
) => AgentStatusNotification(
  id: _inboxNotificationId,
  title: 'New Inbox Reply',
  body: newReplies == 1
      ? 'An agent answered a question. Open the inbox to read it.'
      : 'Agents answered $newReplies questions. Open the inbox to read them.',
  payload: encodeInboxNotificationPayload(),
);

/// Shows a system notification when replies arrive while the inbox page is
/// hidden. The body never contains the reply text. The shell watches it for
/// its whole life, so it does not need `keepAlive`, which would forbid
/// listening to the auto-disposed unread count.
@riverpod
void inboxReplyNotificationCoordinator(Ref ref) {
  final presenter = ref.watch(agentStatusNotificationPresenterProvider);
  final windowActivator = ref.watch(
    agentStatusNotificationWindowActivatorProvider,
  );
  final tracker = InboxReplyNotificationTracker();
  Future<void>? initializing;

  Future<void> ensureInitialized() => initializing ??= presenter.initialize(
    onSelected: (payload) {
      if (!isInboxNotificationPayload(payload)) return;
      unawaited(
        windowActivator.showAndFocus().then((_) {
          if (ref.mounted) ref.read(inboxNavigationProvider.notifier).open();
        }),
      );
    },
  );

  ref.listen(inboxUnreadReplyCountProvider, (_, unread) {
    if (unread == null) return;
    final fresh = tracker.observe(
      unread,
      // The page being open is not enough: a hidden or unfocused window
      // means nobody is reading it.
      inboxVisible:
          ref.read(inboxNavigationProvider).visible &&
          ref.read(inboxWindowFocusProvider).isForeground,
    );
    // Replies are agent answers, so they follow the agent notifications toggle.
    final enabled = ref
        .read(settingsControllerProvider)
        .agents
        .agentStatusNotificationsEnabled;
    if (fresh == 0 || !enabled) return;
    unawaited(
      ensureInitialized().then(
        (_) => presenter.show(inboxReplyNotification(fresh)),
      ),
    );
  }, fireImmediately: true);
}
