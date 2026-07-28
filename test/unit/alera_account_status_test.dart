import 'package:alera/src/features/account/domain/alera_account_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AleraIdentityProvider', () {
    test('maps supported wire names and rejects unknown providers', () {
      expect(
        AleraIdentityProvider.fromWireName('google'),
        AleraIdentityProvider.google,
      );
      expect(
        AleraIdentityProvider.fromWireName('github'),
        AleraIdentityProvider.github,
      );
      expect(AleraIdentityProvider.fromWireName('other'), isNull);
      expect(AleraIdentityProvider.google.label, 'Google');
      expect(AleraIdentityProvider.github.wireName, 'github');
    });
  });

  group('AleraAccountStatus', () {
    test('parses account identity and push preferences', () {
      final status = AleraAccountStatus.fromRuntime(
        accountStatus: <String, Object?>{
          'connected': true,
          'signInPending': true,
          'account': <String, Object?>{
            'accountId': 'account-1',
            'email': 'user@example.com',
            'providers': <Object?>['google', 'unknown', 'github'],
            'runtimeId': 'runtime-1',
            'pushSubscriptionCount': 2,
          },
        },
        runtimeSettings: <String, Object?>{
          'mobilePushNotifications': <String, Object?>{
            'enabled': true,
            'attention': false,
            'done': true,
            'terminalExit': true,
          },
        },
      );

      expect(status.connected, isTrue);
      expect(status.signInPending, isTrue);
      expect(status.account?.id, 'account-1');
      expect(status.account?.email, 'user@example.com');
      expect(status.account?.providers, <AleraIdentityProvider>{
        AleraIdentityProvider.google,
        AleraIdentityProvider.github,
      });
      expect(status.account?.runtimeId, 'runtime-1');
      expect(status.account?.pushSubscriptionCount, 2);
      expect(status.push.enabled, isTrue);
      expect(status.push.attention, isFalse);
      expect(status.push.done, isTrue);
      expect(status.push.terminalExit, isTrue);
    });

    test('uses safe defaults for missing or malformed optional values', () {
      final status = AleraAccountStatus.fromRuntime(
        accountStatus: <String, Object?>{
          'connected': true,
          'account': <String, Object?>{},
        },
        runtimeSettings: const <String, Object?>{},
      );

      expect(status.connected, isTrue);
      expect(status.signInPending, isFalse);
      expect(status.account?.id, isEmpty);
      expect(status.account?.email, isEmpty);
      expect(status.account?.providers, isEmpty);
      expect(status.account?.runtimeId, isEmpty);
      expect(status.account?.pushSubscriptionCount, 0);
      expect(status.push.enabled, isFalse);
      expect(status.push.attention, isTrue);
      expect(status.push.done, isFalse);
      expect(status.push.terminalExit, isFalse);
    });

    test('requires an account object before reporting connected', () {
      final status = AleraAccountStatus.fromRuntime(
        accountStatus: const <String, Object?>{'connected': true},
        runtimeSettings: const <String, Object?>{},
      );

      expect(status.connected, isFalse);
      expect(status.account, isNull);
    });
  });

  group('MobilePushPreferences', () {
    test('copies selected fields and serializes the complete contract', () {
      final preferences = MobilePushPreferences.defaults.copyWith(
        enabled: true,
        done: true,
        terminalExit: true,
      );

      expect(preferences.enabled, isTrue);
      expect(preferences.attention, isTrue);
      expect(preferences.done, isTrue);
      expect(preferences.terminalExit, isTrue);
      expect(preferences.toJson(), <String, Object?>{
        'enabled': true,
        'attention': true,
        'done': true,
        'terminalExit': true,
      });

      final unchanged = preferences.copyWith();
      expect(unchanged.enabled, preferences.enabled);
      expect(unchanged.attention, preferences.attention);
      expect(unchanged.done, preferences.done);
      expect(unchanged.terminalExit, preferences.terminalExit);
    });
  });
}
