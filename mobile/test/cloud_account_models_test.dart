import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
import 'package:alera_mobile/src/features/accounts/domain/runtime_push_preferences.dart';
import 'package:alera_mobile/src/features/push_notifications/domain/push_navigation_intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Enrollment Adds The Runtime With Safe Notification Defaults', () {
    final result = CloudEnrollmentResult.fromJson(<String, Object?>{
      'account': <String, Object?>{
        'id': 'account-1',
        'email': 'dev@example.com',
        'identities': <Map<String, Object?>>[
          <String, Object?>{'provider': 'google'},
          <String, Object?>{'provider': 'github'},
        ],
      },
      'accessToken': 'access',
      'refreshToken': 'refresh',
      'accessTokenExpiresAt': '2026-08-01T00:00:00Z',
      'runtimeId': 'runtime-1',
    });

    expect(result.session.account.id, 'account-1');
    expect(result.session.account.providers, <String>['google', 'github']);
    expect(result.session.subscriptions.keys, <String>['runtime-1']);
    final defaults = result.session.subscriptions['runtime-1']!;
    expect(defaults.enabled, isTrue);
    expect(defaults.attention, isTrue);
    expect(defaults.done, isFalse);
    expect(defaults.terminalExit, isFalse);
  });

  test('Cloud Session Round Trips Multiple Runtime Preferences', () {
    final session = CloudAccountSession(
      account: const CloudAccountProfile(
        id: 'account-1',
        email: 'dev@example.com',
        providers: <String>['google'],
      ),
      accessToken: 'access',
      refreshToken: 'refresh',
      accessTokenExpiresAt: DateTime.utc(2026, 8),
      subscriptions: const <String, RuntimePushPreferences>{
        'runtime-1': RuntimePushPreferences(),
        'runtime-2': RuntimePushPreferences(
          attention: false,
          done: true,
          terminalExit: true,
        ),
      },
    );

    final decoded = CloudAccountSession.fromJson(session.toJson());

    expect(decoded.subscriptions.length, 2);
    expect(decoded.subscriptions['runtime-2']!.attention, isFalse);
    expect(decoded.subscriptions['runtime-2']!.done, isTrue);
    expect(decoded.subscriptions['runtime-2']!.terminalExit, isTrue);
  });

  test('Push Intent Parses Targets And Protects Terminal Exit Routing', () {
    final terminal = PushNavigationIntent.fromData(<String, Object?>{
      'accountId': 'account-1',
      'runtimeId': 'runtime-1',
      'workspaceId': 'workspace-1',
      'tabId': 'tab-1',
      'eventType': 'waiting',
    });
    final exit = PushNavigationIntent.fromData(<String, Object?>{
      'runtimeId': 'runtime-1',
      'workspaceId': 'workspace-1',
      'tabId': 'tab-1',
      'eventType': 'terminalExit',
    });
    final groupedAttention = PushNavigationIntent.fromData(<String, Object?>{
      'runtimeId': 'runtime-1',
      'category': 'attention',
      'eventType': 'grouped',
    });

    expect(terminal.shouldOpenTerminal, isTrue);
    expect(terminal.eventKind, PushEventKind.attention);
    expect(exit.shouldOpenTerminal, isFalse);
    expect(exit.eventKind, PushEventKind.terminalExit);
    expect(groupedAttention.eventKind, PushEventKind.attention);
  });

  test('Push Intent Rejects Payload Without Runtime', () {
    expect(
      () =>
          PushNavigationIntent.fromData(<String, Object?>{'eventType': 'done'}),
      throwsFormatException,
    );
  });
}
