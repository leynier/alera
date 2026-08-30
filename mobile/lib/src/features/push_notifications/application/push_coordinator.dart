import 'dart:async';

import 'package:alera_mobile/src/features/accounts/application/cloud_account_providers.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_accounts_controller.dart';
import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
import 'package:alera_mobile/src/features/push_notifications/application/pending_push_intent_controller.dart';
import 'package:alera_mobile/src/features/push_notifications/application/push_notification_providers.dart';
import 'package:alera_mobile/src/features/push_notifications/infra/push_messaging_service.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'push_coordinator.g.dart';

enum PushCoordinationStatus {
  unavailable,
  idle,
  syncing,
  ready,
  permissionDenied,
  error,
}

class const PushCoordinationState(
  final PushCoordinationStatus status, {
  final String? detail,
});

@Riverpod(keepAlive: true)
class PushCoordinator extends _$PushCoordinator {
  bool _disposed = false;
  bool _reconciling = false;
  bool _reconcileAgain = false;
  Completer<void>? _reconcileDone;

  @override
  Future<PushCoordinationState> build() async {
    final messaging = ref.watch(pushMessagingServiceProvider);
    final notifications = ref.watch(mobileLocalNotificationServiceProvider);
    await notifications.initialize(
      onSelected: (intent) {
        ref
            .read(pendingPushIntentControllerProvider.notifier)
            .setIntent(intent);
      },
    );
    final foregroundSub = messaging.foregroundMessages.listen(
      notifications.show,
    );
    final openedSub = messaging.openedIntents.listen((intent) {
      ref.read(pendingPushIntentControllerProvider.notifier).setIntent(intent);
    });
    final refreshSub = messaging.tokenRefresh.listen((_) {
      unawaited(reconcile());
    });
    ref
      ..onDispose(() {
        _disposed = true;
      })
      ..onDispose(foregroundSub.cancel)
      ..onDispose(openedSub.cancel)
      ..onDispose(refreshSub.cancel)
      ..listen(cloudAccountsControllerProvider, (previous, next) {
        if (previous?.hasValue == true &&
            next.hasValue &&
            previous?.value != next.value) {
          unawaited(reconcile());
        }
      });
    final initialIntent = await messaging.initialIntent();
    if (initialIntent != null) {
      ref
          .read(pendingPushIntentControllerProvider.notifier)
          .setIntent(initialIntent);
    }
    if (!messaging.isAvailable) {
      return const PushCoordinationState(
        .unavailable,
        detail: 'Firebase configuration is missing',
      );
    }
    final sessions = await ref.read(cloudAccountsControllerProvider.future);
    return _synchronize(sessions);
  }

  Future<void> reconcile() async {
    if (_disposed) {
      return;
    }
    if (_reconciling) {
      _reconcileAgain = true;
      final pending = _reconcileDone;
      if (pending != null) {
        await pending.future;
      }
      return;
    }
    _reconciling = true;
    final done = Completer<void>();
    _reconcileDone = done;
    try {
      do {
        _reconcileAgain = false;
        if (_disposed) {
          return;
        }
        state = const AsyncData(PushCoordinationState(.syncing));
        final sessions = await ref.read(cloudAccountsControllerProvider.future);
        final synchronized = await _synchronize(sessions);
        if (_disposed) {
          return;
        }
        state = AsyncData(synchronized);
      } while (_reconcileAgain);
    } on Object catch (error, stackTrace) {
      if (!_disposed) {
        state = AsyncError(error, stackTrace);
      }
    } finally {
      _reconciling = false;
      _reconcileDone = null;
      done.complete();
    }
  }

  Future<PushCoordinationState> _synchronize(
    List<CloudAccountSession> sessions,
  ) async {
    final messaging = ref.read(pushMessagingServiceProvider);
    final accounts = ref.read(cloudAccountsControllerProvider.notifier);
    final api = ref.read(aleraCloudApiProvider);
    if (!messaging.isAvailable) {
      return const PushCoordinationState(
        .unavailable,
        detail: 'Firebase configuration is missing',
      );
    }
    final currentSessions = <CloudAccountSession>[];
    for (var session in sessions) {
      final current = await accounts.sessionForRequest(session.account.id);
      if (_disposed) {
        return const PushCoordinationState(.idle);
      }
      if (current == null) {
        continue;
      }
      session = current;
      currentSessions.add(session);
      for (final entry in session.subscriptions.entries) {
        if (!entry.value.hasEnabledCategory) {
          await api.deleteSubscription(session: session, runtimeId: entry.key);
        }
      }
      if (!session.subscriptions.values.any(
        (preferences) => preferences.hasEnabledCategory,
      )) {
        await api.deletePushToken(session);
      }
    }
    final active = currentSessions
        .where(
          (session) => session.subscriptions.values.any(
            (preferences) => preferences.hasEnabledCategory,
          ),
        )
        .toList(growable: false);
    if (active.isEmpty) {
      return const PushCoordinationState(.idle);
    }
    final permission = await messaging.requestPermission();
    if (_disposed) {
      return const PushCoordinationState(.idle);
    }
    if (permission != PushPermissionState.authorized) {
      return const PushCoordinationState(
        .permissionDenied,
        detail: 'Notification permission is off',
      );
    }
    final token = await messaging.token();
    if (_disposed) {
      return const PushCoordinationState(.idle);
    }
    if (token == null || token.trim().isEmpty) {
      return const PushCoordinationState(
        .error,
        detail: 'Firebase did not return a device token',
      );
    }
    for (final session in active) {
      if (_disposed) {
        return const PushCoordinationState(.idle);
      }
      await api.registerPushToken(
        session: session,
        token: token,
        platform: _platformName(),
      );
      for (final entry in session.subscriptions.entries) {
        if (_disposed) {
          return const PushCoordinationState(.idle);
        }
        if (!entry.value.hasEnabledCategory) {
          continue;
        }
        await api.putSubscription(
          session: session,
          runtimeId: entry.key,
          preferences: entry.value,
        );
      }
    }
    return const PushCoordinationState(.ready);
  }

  String _platformName() {
    return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
  }
}
