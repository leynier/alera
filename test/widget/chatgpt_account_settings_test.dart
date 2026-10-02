import 'dart:async';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/settings/presentation/panes/chatgpt_account_settings.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/uri/external_uri_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _authorizationUrl =
    'https://auth.openai.com/api/accounts/authorize?id_token_hint=secret';

Map<String, Object?> _account(
  String id,
  String label, {
  bool connected = true,
  bool planEnabled = true,
}) => <String, Object?>{
  'clientId': id,
  'label': label,
  'connected': connected,
  'planEnabled': planEnabled,
};

void main() {
  testWidgets('offers sign-in when no account is connected', (tester) async {
    final client = _FakeChatGptClient();
    await _pump(tester, client);

    expect(find.text('Connect Account'), findsOneWidget);
    expect(find.text('Continue with ChatGPT'), findsOneWidget);
    expect(find.text('Manage usage'), findsNothing);
    expect(find.text('Sign Out'), findsNothing);
  });

  testWidgets('waits for a silent runtime without animating', (tester) async {
    final client = _FakeChatGptClient()..silent = true;
    await _pump(tester, client);

    expect(
      find.text('Checking for ChatGPT accounts on this computer.'),
      findsOne,
    );
    final button = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Continue with ChatGPT'),
        matching: find.byWidgetPredicate((w) => w is OutlinedButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('hides account controls on a runtime without support', (
    tester,
  ) async {
    final client = _FakeChatGptClient()..supported = false;
    await _pump(tester, client);

    expect(find.textContaining('can’t connect ChatGPT'), findsOneWidget);
    expect(find.text('Continue with ChatGPT'), findsNothing);
    expect(client.requests, isEmpty);
  });

  testWidgets('marks the active account among same-email registrations', (
    tester,
  ) async {
    final client = _FakeChatGptClient()
      ..status = <String, Object?>{
        'activeClientId': 'a',
        'accounts': <Object?>[
          _account('a', 'me@example.com (1)'),
          _account('b', 'me@example.com (2)'),
        ],
      };
    await _pump(tester, client);

    final active = find.byKey(const ValueKey<String>('chatgpt-account-a'));
    final other = find.byKey(const ValueKey<String>('chatgpt-account-b'));
    expect(
      find.descendant(of: active, matching: find.text('Active')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: active, matching: find.text('Using ChatGPT plan.')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: other, matching: find.text('Active')),
      findsNothing,
    );
    expect(
      find.descendant(of: other, matching: find.text('Use Account')),
      findsOneWidget,
    );
    expect(find.text('Manage usage'), findsOneWidget);
    expect(find.text('Add Account'), findsOneWidget);
  });

  testWidgets('switching accounts selects it and notifies the parent', (
    tester,
  ) async {
    var changes = 0;
    final client = _FakeChatGptClient()
      ..status = <String, Object?>{
        'activeClientId': 'a',
        'accounts': <Object?>[_account('a', 'A (1)'), _account('b', 'B (2)')],
      };
    client.onRequest['select'] = (payload) {
      client.status = <String, Object?>{
        ...client.status,
        'activeClientId': 'b',
      };
      return <String, Object?>{'selected': true};
    };
    await _pump(tester, client, onAccountChanged: () => changes++);

    await tester.tap(find.text('Use Account'));
    await tester.pumpAndSettle();

    expect(client.payloads['select'], <String, Object?>{'clientId': 'b'});
    expect(changes, 1);
    final b = find.byKey(const ValueKey<String>('chatgpt-account-b'));
    expect(find.descendant(of: b, matching: find.text('Active')), findsOne);
  });

  testWidgets('signed-out account offers reconnect for that registration', (
    tester,
  ) async {
    final launcher = _FakeLauncher();
    final client = _FakeChatGptClient()
      ..status = <String, Object?>{
        'activeClientId': null,
        'accounts': <Object?>[_account('a', 'A (1)', connected: false)],
      };
    client.onRequest['signIn'] = (_) {
      client.status = <String, Object?>{...client.status, 'pending': true};
      return <String, Object?>{'authorizationUrl': _authorizationUrl};
    };
    await _pump(tester, client, launcher: launcher);

    expect(find.text('Signed out.'), findsOneWidget);
    final row = find.byKey(const ValueKey<String>('chatgpt-account-a'));
    await tester.tap(
      find.descendant(of: row, matching: find.text('Continue with ChatGPT')),
    );
    await tester.pump();
    await tester.pump();

    expect(client.payloads['signIn'], <String, Object?>{'clientId': 'a'});
    expect(launcher.opened.single.toString(), _authorizationUrl);
    expect(
      find.text('Finish signing in to ChatGPT in your browser.'),
      findsOneWidget,
    );
    await _stopPolling(tester, client);
  });

  testWidgets('pending sign-in polls, disables actions, and can be cancelled', (
    tester,
  ) async {
    final client = _FakeChatGptClient()
      ..status = <String, Object?>{
        'activeClientId': 'a',
        'pending': true,
        'accounts': <Object?>[_account('a', 'A (1)')],
      };
    client.onRequest['cancel'] = (_) {
      client.status = <String, Object?>{...client.status, 'pending': false};
      return <String, Object?>{};
    };
    await _pump(tester, client, settle: false);
    await tester.pump();

    final signOut = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Sign Out'),
        matching: find.byType(TextButton),
      ),
    );
    expect(signOut.onPressed, isNull);
    final before = client.count('status');
    await tester.pump(const Duration(seconds: 1));
    expect(client.count('status'), greaterThan(before));

    await tester.tap(find.text('Cancel Sign-In'));
    await tester.pumpAndSettle();

    expect(client.count('cancel'), 1);
    expect(find.text('Cancel Sign-In'), findsNothing);
  });

  testWidgets('rejects a sign-in link that is not the OpenAI authorize URL', (
    tester,
  ) async {
    final launcher = _FakeLauncher();
    final client = _FakeChatGptClient();
    client.onRequest['signIn'] = (_) => <String, Object?>{
      'authorizationUrl': 'https://example.com/api/accounts/authorize',
    };
    await _pump(tester, client, launcher: launcher);

    await tester.tap(find.text('Continue with ChatGPT'));
    await tester.pumpAndSettle();

    expect(launcher.opened, isEmpty);
    expect(client.count('cancel'), 1);
    expect(find.text('ChatGPT returned an invalid sign-in link.'), findsOne);
  });

  testWidgets('cancels the attempt when the browser cannot open', (
    tester,
  ) async {
    final launcher = _FakeLauncher()..fail = true;
    final client = _FakeChatGptClient();
    client.onRequest['signIn'] = (_) => <String, Object?>{
      'authorizationUrl': _authorizationUrl,
    };
    await _pump(tester, client, launcher: launcher);

    await tester.tap(find.text('Continue with ChatGPT'));
    await tester.pumpAndSettle();

    expect(client.count('cancel'), 1);
    expect(find.textContaining('browser couldn’t be opened'), findsOneWidget);
  });

  testWidgets('sign out reports an unconfirmed revocation', (tester) async {
    var changes = 0;
    final client = _FakeChatGptClient()
      ..status = <String, Object?>{
        'activeClientId': 'a',
        'accounts': <Object?>[_account('a', 'A (1)')],
      };
    client.onRequest['signOut'] = (_) {
      client.status = <String, Object?>{
        'activeClientId': null,
        'error': 'Signed out locally. Remote revocation was not confirmed.',
        'accounts': <Object?>[_account('a', 'A (1)', connected: false)],
      };
      return <String, Object?>{'signedOut': true, 'revocationConfirmed': false};
    };
    await _pump(tester, client, onAccountChanged: () => changes++);

    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();

    expect(client.payloads['signOut'], <String, Object?>{'clientId': 'a'});
    expect(changes, 1);
    expect(find.textContaining('revocation was not confirmed'), findsOne);
    expect(find.text('Signed out.'), findsOneWidget);
  });

  testWidgets('shows the plan notice once and acknowledges it', (tester) async {
    final client = _FakeChatGptClient()
      ..status = <String, Object?>{
        'activeClientId': 'a',
        'showPlanNotice': true,
        'accounts': <Object?>[_account('a', 'A (1)')],
      };
    client.onRequest['acknowledgePlan'] = (_) {
      client.status = <String, Object?>{
        ...client.status,
        'showPlanNotice': false,
      };
      return <String, Object?>{};
    };
    await _pump(tester, client);

    expect(find.text('You’re using your ChatGPT plan'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    expect(find.text('You’re using your ChatGPT plan'), findsNothing);
    expect(client.count('acknowledgePlan'), 1);
  });

  testWidgets('opens ChatGPT usage settings', (tester) async {
    final launcher = _FakeLauncher();
    final client = _FakeChatGptClient()
      ..status = <String, Object?>{
        'activeClientId': 'a',
        'accounts': <Object?>[_account('a', 'A (1)')],
      };
    await _pump(tester, client, launcher: launcher);

    await tester.tap(find.text('Manage usage'));
    await tester.pump();

    expect(
      launcher.opened.single,
      Uri.parse('https://chatgpt.com/settings/usage'),
    );
  });
}

Future<void> _pump(
  WidgetTester tester,
  _FakeChatGptClient client, {
  _FakeLauncher? launcher,
  VoidCallback? onAccountChanged,
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChatGptAccountSettings(
              client: client,
              launcher: launcher ?? _FakeLauncher(),
              onAccountChanged: onAccountChanged ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Future<void> _stopPolling(
  WidgetTester tester,
  _FakeChatGptClient client,
) async {
  client.status = <String, Object?>{...client.status, 'pending': false};
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

class _FakeLauncher implements ExternalUriLauncher {
  final List<Uri> opened = <Uri>[];
  bool fail = false;

  @override
  Future<void> open(Uri uri) async {
    if (fail) throw StateError('Could not open URI: $uri');
    opened.add(uri);
  }
}

class _FakeChatGptClient
    implements RuntimeHostClient, RuntimeHostCapabilityClient {
  bool supported = true;
  bool silent = false;
  Map<String, Object?> status = <String, Object?>{
    'activeClientId': null,
    'accounts': <Object?>[],
  };
  final Map<String, Map<String, Object?> Function(Map<String, Object?>)>
  onRequest = <String, Map<String, Object?> Function(Map<String, Object?>)>{};
  final List<String> requests = <String>[];
  final Map<String, Map<String, Object?>> payloads =
      <String, Map<String, Object?>>{};

  int count(String action) => requests.where((r) => r == action).length;

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => const Stream.empty();

  @override
  Future<bool> supportsRuntimeCapability(String capability) async =>
      supported && capability == aleraRuntimeHostAiAssistChatGptCapability;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    final action = type.replaceFirst('aiAssist.chatgpt.', '');
    requests.add(action);
    if (silent) return Completer<Object?>().future;
    payloads[action] = payload;
    if (action == 'status') return status;
    return onRequest[action]?.call(payload) ?? <String, Object?>{};
  }
}
