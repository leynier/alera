import 'dart:async';

import 'package:alera_mobile/src/features/accounts/application/cloud_account_providers.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_account_repository.dart';
import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
import 'package:alera_mobile/src/features/accounts/domain/runtime_push_preferences.dart';
import 'package:alera_mobile/src/features/accounts/infra/alera_cloud_api.dart';
import 'package:alera_mobile/src/features/push_notifications/application/pending_push_intent_controller.dart';
import 'package:alera_mobile/src/features/push_notifications/application/push_coordinator.dart';
import 'package:alera_mobile/src/features/push_notifications/application/push_notification_providers.dart';
import 'package:alera_mobile/src/features/push_notifications/domain/push_navigation_intent.dart';
import 'package:alera_mobile/src/features/push_notifications/infra/mobile_local_notification_service.dart';
import 'package:alera_mobile/src/features/push_notifications/infra/push_messaging_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Reconciles Every Account And Runtime With One FCM Token', () async {
    final repository = _MemoryCloudAccountRepository(<CloudAccountSession>[
      _session('account-1', 'runtime-1'),
      _session('account-2', 'runtime-2'),
    ]);
    final api = _FakeCloudApi();
    final messaging = _FakePushMessaging();
    final container = ProviderContainer(
      overrides: [
        cloudAccountRepositoryProvider.overrideWithValue(repository),
        aleraCloudApiProvider.overrideWithValue(api),
        pushMessagingServiceProvider.overrideWithValue(messaging),
        mobileLocalNotificationServiceProvider.overrideWithValue(
          _FakeLocalNotifications(),
        ),
      ],
    );
    addTearDown(() {
      container.dispose();
      messaging.dispose();
    });

    final state = await container.read(pushCoordinatorProvider.future);

    expect(state.status, PushCoordinationStatus.ready);
    expect(api.registeredAccounts, <String>['account-1', 'account-2']);
    expect(api.subscriptions, <String>[
      'account-1/runtime-1',
      'account-2/runtime-2',
    ]);

    messaging.refresh.add('rotated-token');
    await _waitFor(() => api.registeredAccounts.length == 4);
    expect(api.lastToken, 'fcm-token');
  });

  test('Foreground Messages Always Use The Local Presenter', () async {
    final repository = _MemoryCloudAccountRepository(<CloudAccountSession>[
      _session('account-1', 'runtime-1'),
    ]);
    final messaging = _FakePushMessaging();
    final notifications = _FakeLocalNotifications();
    final container = ProviderContainer(
      overrides: [
        cloudAccountRepositoryProvider.overrideWithValue(repository),
        aleraCloudApiProvider.overrideWithValue(_FakeCloudApi()),
        pushMessagingServiceProvider.overrideWithValue(messaging),
        mobileLocalNotificationServiceProvider.overrideWithValue(notifications),
      ],
    );
    addTearDown(() {
      container.dispose();
      messaging.dispose();
    });
    await container.read(pushCoordinatorProvider.future);
    final message = PushMessage(
      title: 'Codex Needs Attention',
      body: 'Workspace App In Alera',
      data: const <String, Object?>{
        'runtimeId': 'runtime-1',
        'eventType': 'waiting',
      },
    );

    messaging.foreground.add(message);
    await _waitFor(() => notifications.messages.isNotEmpty);
    messaging.opened.add(message.navigationIntent!);
    await _waitFor(
      () => container.read(pendingPushIntentControllerProvider) != null,
    );

    expect(notifications.messages.single, same(message));
    expect(
      container.read(pendingPushIntentControllerProvider)?.runtimeId,
      'runtime-1',
    );
  });

  test('Disabling Every Category Removes Remote Push State', () async {
    final disabled = _session(
      'account-1',
      'runtime-1',
      preferences: const RuntimePushPreferences(
        attention: false,
        done: false,
        terminalExit: false,
      ),
    );
    final repository = _MemoryCloudAccountRepository(<CloudAccountSession>[
      disabled,
    ]);
    final api = _FakeCloudApi();
    final messaging = _FakePushMessaging();
    final container = ProviderContainer(
      overrides: [
        cloudAccountRepositoryProvider.overrideWithValue(repository),
        aleraCloudApiProvider.overrideWithValue(api),
        pushMessagingServiceProvider.overrideWithValue(messaging),
        mobileLocalNotificationServiceProvider.overrideWithValue(
          _FakeLocalNotifications(),
        ),
      ],
    );
    addTearDown(() {
      container.dispose();
      messaging.dispose();
    });

    final state = await container.read(pushCoordinatorProvider.future);

    expect(state.status, PushCoordinationStatus.idle);
    expect(api.deletedSubscriptions, <String>['account-1/runtime-1']);
    expect(api.deletedPushTokens, <String>['account-1']);
    expect(api.registeredAccounts, isEmpty);
    expect(messaging.permissionRequests, 0);
  });

  test('Concurrent Reconcile Waits For The Latest Cloud Pass', () async {
    final repository = _MemoryCloudAccountRepository(<CloudAccountSession>[
      _session('account-1', 'runtime-1'),
    ]);
    final api = _FakeCloudApi();
    final messaging = _FakePushMessaging();
    final container = ProviderContainer(
      overrides: [
        cloudAccountRepositoryProvider.overrideWithValue(repository),
        aleraCloudApiProvider.overrideWithValue(api),
        pushMessagingServiceProvider.overrideWithValue(messaging),
        mobileLocalNotificationServiceProvider.overrideWithValue(
          _FakeLocalNotifications(),
        ),
      ],
    );
    addTearDown(() {
      container.dispose();
      messaging.dispose();
    });
    await container.read(pushCoordinatorProvider.future);
    api.registerGate = Completer<void>();

    final first = container.read(pushCoordinatorProvider.notifier).reconcile();
    await _waitFor(() => api.registeredAccounts.length == 2);
    var secondFinished = false;
    final second = container
        .read(pushCoordinatorProvider.notifier)
        .reconcile()
        .whenComplete(() => secondFinished = true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(secondFinished, isFalse);

    api.registerGate!.complete();
    await Future.wait(<Future<void>>[first, second]);

    expect(api.registeredAccounts, hasLength(3));
    expect(secondFinished, isTrue);
  });
}

CloudAccountSession _session(
  String accountId,
  String runtimeId, {
  RuntimePushPreferences preferences = const RuntimePushPreferences(),
}) {
  return CloudAccountSession(
    account: CloudAccountProfile(
      id: accountId,
      email: '$accountId@example.com',
    ),
    accessToken: 'access-$accountId',
    refreshToken: 'refresh-$accountId',
    accessTokenExpiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    subscriptions: <String, RuntimePushPreferences>{runtimeId: preferences},
  );
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Condition Was Not Reached');
}

class _MemoryCloudAccountRepository implements CloudAccountRepository {
  _MemoryCloudAccountRepository(List<CloudAccountSession> sessions)
    : sessions = <CloudAccountSession>[...sessions];

  final List<CloudAccountSession> sessions;

  @override
  Future<String> getOrCreateInstallationId() async => 'installation-1';

  @override
  Future<List<CloudAccountSession>> loadSessions() async =>
      List<CloudAccountSession>.of(sessions);

  @override
  Future<void> removeSession(String accountId) async {
    sessions.removeWhere((session) => session.account.id == accountId);
  }

  @override
  Future<void> saveSession(CloudAccountSession session) async {
    sessions.removeWhere((item) => item.account.id == session.account.id);
    sessions.add(session);
  }
}

class _FakeCloudApi implements AleraCloudApi {
  final List<String> registeredAccounts = <String>[];
  final List<String> subscriptions = <String>[];
  final List<String> deletedSubscriptions = <String>[];
  final List<String> deletedPushTokens = <String>[];
  Completer<void>? registerGate;
  String? lastToken;

  @override
  Future<CloudAccountProfile> accountStatus(
    CloudAccountSession session,
  ) async => session.account;

  @override
  Future<void> deleteSubscription({
    required CloudAccountSession session,
    required String runtimeId,
  }) async {
    deletedSubscriptions.add('${session.account.id}/$runtimeId');
  }

  @override
  Future<void> putSubscription({
    required CloudAccountSession session,
    required String runtimeId,
    required RuntimePushPreferences preferences,
  }) async {
    subscriptions.add('${session.account.id}/$runtimeId');
  }

  @override
  Future<void> deletePushToken(CloudAccountSession session) async {
    deletedPushTokens.add(session.account.id);
  }

  @override
  Future<void> registerPushToken({
    required CloudAccountSession session,
    required String token,
    required String platform,
  }) async {
    registeredAccounts.add(session.account.id);
    lastToken = token;
    final gate = registerGate;
    if (gate != null) {
      await gate.future;
    }
  }

  @override
  Future<CloudAccountSession> refreshSession(
    CloudAccountSession session,
  ) async => session;

  @override
  Future<void> revokeSession(CloudAccountSession session) async {}

  @override
  Future<CloudEnrollmentResult> redeemEnrollment({
    required String code,
    required String deviceId,
    required String deviceName,
  }) {
    throw UnimplementedError();
  }
}

class _FakePushMessaging implements PushMessagingService {
  final StreamController<String> refresh = StreamController<String>.broadcast();
  final StreamController<PushMessage> foreground =
      StreamController<PushMessage>.broadcast();
  final StreamController<PushNavigationIntent> opened =
      StreamController<PushNavigationIntent>.broadcast();
  int permissionRequests = 0;

  @override
  Stream<PushMessage> get foregroundMessages => foreground.stream;

  @override
  Future<PushNavigationIntent?> initialIntent() async => null;

  @override
  bool get isAvailable => true;

  @override
  Stream<PushNavigationIntent> get openedIntents => opened.stream;

  @override
  Future<PushPermissionState> requestPermission() async {
    permissionRequests += 1;
    return PushPermissionState.authorized;
  }

  @override
  Future<String?> token() async => 'fcm-token';

  @override
  Stream<String> get tokenRefresh => refresh.stream;

  void dispose() {
    refresh.close();
    foreground.close();
    opened.close();
  }
}

class _FakeLocalNotifications implements MobileLocalNotificationService {
  final List<PushMessage> messages = <PushMessage>[];

  @override
  Future<void> initialize({
    required PushNotificationSelectionHandler onSelected,
  }) async {}

  @override
  Future<void> show(PushMessage message) async {
    messages.add(message);
  }
}
