import 'dart:async';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/chips/alera_chip.dart';
import 'package:alera/src/features/account/application/alera_account_providers.dart';
import 'package:alera/src/features/account/infra/runtime_alera_account_repository.dart';
import 'package:alera/src/features/account/presentation/account_settings_pane.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final provider in <String>['google', 'github']) {
    testWidgets(
      'rebuilds to the signed-in $provider account after aleraAccountChanged',
      (tester) async {
        final client = _FakeAccountRuntimeHostClient();
        await _pumpPane(tester, client);

        expect(find.text('Continue With Google'), findsOneWidget);
        expect(find.text('Continue With GitHub'), findsOneWidget);
        expect(find.text('Sign Out'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        client.signIn(provider);
        client.emit(
          const RuntimeHostEvent('aleraAccountChanged', <String, Object?>{
            'connected': true,
          }),
        );
        await tester.pump();
        expect(
          find.byType(CircularProgressIndicator),
          findsNothing,
          reason:
              'successful login must not flash a loading or signed-out tree',
        );
        await tester.pump(const Duration(milliseconds: 30));
        await tester.pumpAndSettle();

        expect(find.text('Continue With Google'), findsNothing);
        expect(find.text('Continue With GitHub'), findsNothing);
        expect(find.text('user@example.com'), findsOneWidget);
        expect(find.text('Alera Account'), findsOneWidget);
        expect(
          find.widgetWithText(
            AleraChip,
            provider == 'google' ? 'Google' : 'GitHub',
          ),
          findsOneWidget,
        );
        expect(find.widgetWithText(OutlinedButton, 'Sign Out'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );
  }

  testWidgets('does not treat an unrelated event as a sign-out', (
    tester,
  ) async {
    final client = _FakeAccountRuntimeHostClient()..signIn('google');
    await _pumpPane(tester, client);

    expect(find.text('user@example.com'), findsOneWidget);

    client.emit(const RuntimeHostEvent('projectsChanged', <String, Object?>{}));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpAndSettle();

    expect(find.text('user@example.com'), findsOneWidget);
    expect(find.text('Continue With Google'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

Future<void> _pumpPane(
  WidgetTester tester,
  _FakeAccountRuntimeHostClient client,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aleraAccountRepositoryProvider.overrideWithValue(
          RuntimeAleraAccountRepository(
            client,
            coalescer: RuntimeChangeCoalescer(
              debounce: const Duration(milliseconds: 5),
              maxDelay: const Duration(milliseconds: 20),
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: aleraDarkTheme,
        home: const Scaffold(body: AccountSettingsPane()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _FakeAccountRuntimeHostClient implements RuntimeHostClient {
  Map<String, Object?> _accountStatus = <String, Object?>{
    'connected': false,
    'signInPending': false,
  };

  final StreamController<RuntimeHostEvent> _events =
      StreamController<RuntimeHostEvent>.broadcast();

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  void emit(RuntimeHostEvent event) => _events.add(event);

  void signIn(String provider) {
    _accountStatus = <String, Object?>{
      'connected': true,
      'signInPending': false,
      'account': <String, Object?>{
        'accountId': 'account',
        'email': 'user@example.com',
        'providers': <String>[provider],
        'runtimeId': 'runtime',
      },
    };
  }

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    return switch (type) {
      'account.status' => _accountStatus,
      'runtimeSettings.get' => const <String, Object?>{},
      _ => const <String, Object?>{},
    };
  }
}
