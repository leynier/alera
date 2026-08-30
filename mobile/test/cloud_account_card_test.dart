import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
import 'package:alera_mobile/src/features/accounts/domain/runtime_push_preferences.dart';
import 'package:alera_mobile/src/features/accounts/presentation/cloud_account_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lays out subscribed runtimes inside a scrolling account list', (
    tester,
  ) async {
    final session = CloudAccountSession(
      account: const CloudAccountProfile(
        id: 'account-1',
        email: 'account@example.com',
        providers: <String>['google'],
      ),
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      accessTokenExpiresAt: .utc(2030),
      subscriptions: const <String, RuntimePushPreferences>{
        'runtime-1': RuntimePushPreferences(),
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: .dark(),
        home: Scaffold(
          body: ListView(
            children: <Widget>[
              CloudAccountCard(
                session: session,
                hosts: const [],
                onPreferencesChanged: (_, _) async {},
                onAction: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('account@example.com'), findsOneWidget);
    expect(find.text('Unpaired runtime'), findsOneWidget);
  });
}
