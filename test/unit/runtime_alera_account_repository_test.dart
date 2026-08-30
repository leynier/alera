import 'dart:async';

import 'package:alera/src/features/account/domain/alera_account_status.dart';
import 'package:alera/src/features/account/infra/runtime_alera_account_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads account and runtime push status', () async {
    final client = _FakeRuntimeHostClient(<String, Object?>{
      'account.status': <String, Object?>{
        'connected': true,
        'account': <String, Object?>{
          'accountId': 'account',
          'email': 'user@example.com',
          'providers': <String>['google'],
          'runtimeId': 'runtime',
        },
      },
      'runtimeSettings.get': <String, Object?>{
        'mobilePushNotifications': <String, Object?>{'enabled': true},
      },
    });
    final repository = RuntimeAleraAccountRepository(client);

    final status = await repository.status();

    expect(status.connected, isTrue);
    expect(status.account?.email, 'user@example.com');
    expect(status.push.enabled, isTrue);
    expect((await repository.watchStatus().first).account?.id, 'account');
  });

  test('starts provider flows and validates the authorization URL', () async {
    final client = _FakeRuntimeHostClient(<String, Object?>{
      'account.signIn.start': <String, Object?>{
        'authorizationUrl': 'https://accounts.example/sign-in',
      },
      'account.link.start': <String, Object?>{
        'authorizationUrl': 'https://accounts.example/link',
      },
    });
    final repository = RuntimeAleraAccountRepository(client);

    expect(
      await repository.startSignIn(.google),
      Uri.parse('https://accounts.example/sign-in'),
    );
    expect(
      await repository.startLink(.github),
      Uri.parse('https://accounts.example/link'),
    );
    expect(client.calls[0].payload, <String, Object?>{'provider': 'google'});
    expect(client.calls[1].payload, <String, Object?>{'provider': 'github'});

    client.responses['account.signIn.start'] = const <String, Object?>{};
    await expectLater(repository.startSignIn(.google), throwsFormatException);
    client.responses['account.signIn.start'] = <String, Object?>{
      'authorizationUrl': 'relative',
    };
    await expectLater(repository.startSignIn(.google), throwsFormatException);
  });

  test('sends account mutations and complete push preferences', () async {
    final client = _FakeRuntimeHostClient(<String, Object?>{
      'account.signIn.cancel': const <String, Object?>{},
      'account.signOut': const <String, Object?>{},
      'account.delete': const <String, Object?>{},
      'account.transfer.confirm': const <String, Object?>{},
      'runtimeSettings.update': const <String, Object?>{},
    });
    final repository = RuntimeAleraAccountRepository(client);

    await repository.cancelSignIn();
    await repository.signOut();
    await repository.deleteAccount();
    await repository.transferRuntime('target');
    await repository.updatePush(
      const MobilePushPreferences(
        enabled: true,
        attention: false,
        done: true,
        terminalExit: true,
      ),
    );

    expect(client.calls.map((call) => call.type), <String>[
      'account.signIn.cancel',
      'account.signOut',
      'account.delete',
      'account.transfer.confirm',
      'runtimeSettings.update',
    ]);
    expect(client.calls[3].payload, <String, Object?>{
      'targetAccountId': 'target',
    });
    expect(client.calls[4].payload, <String, Object?>{
      'mobilePushNotifications': <String, Object?>{
        'enabled': true,
        'attention': false,
        'done': true,
        'terminalExit': true,
      },
    });
  });

  test('surfaces sign-in failure events', () async {
    final client = _FakeRuntimeHostClient(const <String, Object?>{});
    final repository = RuntimeAleraAccountRepository(client);
    final failure = repository.watchSignInFailures().first;

    client.addEvent(const RuntimeHostEvent('unrelated', <String, Object?>{}));
    client.addEvent(
      const RuntimeHostEvent('aleraAccountSignInFailed', <String, Object?>{
        'message': 'Provider rejected the request',
      }),
    );

    expect(await failure, 'Provider rejected the request');
  });

  test('rejects non-object runtime responses', () async {
    final client = _FakeRuntimeHostClient(<String, Object?>{
      'account.status': 'invalid',
    });
    final repository = RuntimeAleraAccountRepository(client);

    await expectLater(repository.status(), throwsFormatException);
  });
}

final class const _RuntimeCall(
  final String type,
  final Map<String, Object?> payload,
);

final class _FakeRuntimeHostClient(final Map<String, Object?> responses)
    implements RuntimeHostClient {
  final List<_RuntimeCall> calls = <_RuntimeCall>[];
  final StreamController<RuntimeHostEvent> _events =
      StreamController<RuntimeHostEvent>.broadcast();

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  void addEvent(RuntimeHostEvent event) => _events.add(event);

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    calls.add(_RuntimeCall(type, payload));
    return responses[type];
  }
}
