import 'dart:async';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/mcp_access/application/mcp_access_providers.dart';
import 'package:alera/src/features/mcp_access/domain/mcp_access_repository.dart';
import 'package:alera/src/features/mcp_access/domain/mcp_access_settings.dart';
import 'package:alera/src/features/mcp_access/domain/mcp_grant.dart';
import 'package:alera/src/features/settings/presentation/mcp_access_settings_section.dart';
import 'package:alera/src/features/webhooks/application/webhook_providers.dart';
import 'package:alera/src/features/webhooks/domain/runtime_webhook.dart';
import 'package:alera/src/features/webhooks/domain/webhook_repository.dart';
import 'package:alera/src/features/webhooks/presentation/add_webhook_dialog.dart';
import 'package:alera/src/features/webhooks/presentation/webhooks_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final RuntimeWebhook _allEvents = RuntimeWebhook(
  id: 'wh_all',
  url: 'https://example.com/alera',
  kinds: <String>[for (final kind in RuntimeEventKind.values) kind.wireName],
  status: 'active',
  lastDeliveryAt: DateTime.utc(2026, 10, 9, 12),
);

const RuntimeWebhook _failing = RuntimeWebhook(
  id: 'wh_failing',
  url: 'https://hooks.example.org/ci',
  kinds: <String>['agent.status', 'terminal.exit', 'pullRequest.watch'],
  status: 'failing',
  lastError: 'HTTP 502 from receiver',
);

final Finder _dialogAddButton = find.descendant(
  of: find.byType(AddWebhookDialog),
  matching: find.widgetWithText(FilledButton, 'Add Webhook'),
);

void main() {
  Future<_FakeWebhookRepository> pump(
    WidgetTester tester,
    _FakeWebhookRepository repository, {
    bool accountConnected = true,
  }) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          webhookRepositoryProvider.overrideWithValue(repository),
          mcpAccessRepositoryProvider.overrideWithValue(
            _FakeMcpAccessRepository(accountConnected: accountConnected),
          ),
        ],
        child: MaterialApp(
          theme: aleraDarkTheme,
          home: const Scaffold(
            body: SingleChildScrollView(child: WebhooksSettings()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  FilledButton addButton(WidgetTester tester) {
    return tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Add Webhook'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ),
    );
  }

  testWidgets('lists webhooks with events, status and deliveries', (
    tester,
  ) async {
    await pump(
      tester,
      _FakeWebhookRepository(webhooks: <RuntimeWebhook>[_allEvents, _failing]),
    );

    expect(find.text('Webhooks'), findsOneWidget);
    expect(find.text('https://example.com/alera'), findsOneWidget);
    expect(find.text('https://hooks.example.org/ci'), findsOneWidget);
    expect(find.text('All Events'), findsOneWidget);
    expect(find.text('3 Events'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Failing'), findsOneWidget);
    expect(find.textContaining('Last delivery'), findsOneWidget);
    expect(find.textContaining('No deliveries yet'), findsOneWidget);
    expect(find.text('Last error: HTTP 502 from receiver'), findsOneWidget);
    expect(addButton(tester).onPressed, isNotNull);
  });

  testWidgets('shows an empty state when the account has no webhooks', (
    tester,
  ) async {
    await pump(tester, _FakeWebhookRepository());

    expect(find.text('No webhooks'), findsOneWidget);
  });

  testWidgets('explains and disables webhooks on an older runtime', (
    tester,
  ) async {
    final repository = await pump(
      tester,
      _FakeWebhookRepository(supported: false),
    );

    expect(
      find.textContaining('Update the Alera runtime to use webhooks.'),
      findsOneWidget,
    );
    expect(addButton(tester).onPressed, isNull);
    expect(repository.listCalls, 0);
  });

  testWidgets('asks to sign in before listing webhooks', (tester) async {
    final repository = await pump(
      tester,
      _FakeWebhookRepository(webhooks: <RuntimeWebhook>[_allEvents]),
      accountConnected: false,
    );

    expect(find.textContaining('Sign in to an Alera account'), findsOneWidget);
    expect(find.text('https://example.com/alera'), findsNothing);
    expect(addButton(tester).onPressed, isNull);
    expect(repository.listCalls, 0);
  });

  testWidgets('shows a runtime error from the list', (tester) async {
    await pump(
      tester,
      _FakeWebhookRepository(
        listError: StateError('Sign in to an Alera account first.'),
      ),
    );

    expect(find.text('Webhooks unavailable'), findsOneWidget);
    expect(find.text('Sign in to an Alera account first.'), findsOneWidget);
  });

  testWidgets('adds a webhook and shows its secret only once', (tester) async {
    final repository = await pump(tester, _FakeWebhookRepository());
    expect(repository.listCalls, 1);

    await tester.tap(find.text('Add Webhook'));
    await tester.pumpAndSettle();
    expect(find.text('Webhook URL'), findsOneWidget);

    final urlField = find.byType(TextField);
    await tester.enterText(urlField, 'http://example.com/hooks');
    await tester.tap(_dialogAddButton);
    await tester.pumpAndSettle();
    expect(find.text('Webhook URLs must use https.'), findsOneWidget);
    expect(repository.created, isEmpty);

    await tester.enterText(urlField, 'https://example.com/hooks');
    await tester.tap(find.text('Terminal Exit'));
    await tester.pumpAndSettle();
    await tester.tap(_dialogAddButton);
    await tester.pumpAndSettle();

    final (url, kinds) = repository.created.single;
    expect(url, 'https://example.com/hooks');
    expect(kinds, hasLength(RuntimeEventKind.values.length - 1));
    expect(kinds, isNot(contains('terminal.exit')));

    expect(find.text('Webhook Added'), findsOneWidget);
    expect(find.text('whsec_once'), findsOneWidget);
    expect(find.textContaining("won't see it again"), findsOneWidget);
    expect(find.byTooltip('Copy Secret'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('whsec_once'), findsNothing);
    expect(find.text('https://example.com/hooks'), findsOneWidget);
    expect(repository.listCalls, 2);
  });

  testWidgets('keeps the dialog open until a slow creation answers', (
    tester,
  ) async {
    final repository = _FakeWebhookRepository()..createGate = Completer<void>();
    await pump(tester, repository);
    await tester.tap(find.text('Add Webhook'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'https://example.com/hooks');
    await tester.tap(_dialogAddButton);
    await tester.pump();

    await tester.tap(find.byTooltip('Close'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(find.text('Webhook URL'), findsOneWidget);

    repository.createGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('whsec_once'), findsOneWidget);
  });

  testWidgets('sends every kind as the default when all are selected', (
    tester,
  ) async {
    final repository = await pump(tester, _FakeWebhookRepository());

    await tester.tap(find.text('Add Webhook'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'https://example.com/all');
    await tester.tap(_dialogAddButton);
    await tester.pumpAndSettle();

    expect(repository.created.single.$2, isNull);
  });

  testWidgets('keeps the add dialog open with the runtime error', (
    tester,
  ) async {
    final repository = await pump(
      tester,
      _FakeWebhookRepository(
        createError: StateError('Sign in to an Alera account first.'),
      ),
    );

    await tester.tap(find.text('Add Webhook'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'https://example.com/x');
    await tester.tap(_dialogAddButton);
    await tester.pumpAndSettle();

    expect(find.text('Sign in to an Alera account first.'), findsOneWidget);
    expect(find.text('Webhook URL'), findsOneWidget);
    expect(find.text('Webhook Added'), findsNothing);
    expect(repository.created, hasLength(1));
  });

  testWidgets('deletes a webhook only after confirmation', (tester) async {
    final repository = await pump(
      tester,
      _FakeWebhookRepository(webhooks: <RuntimeWebhook>[_allEvents]),
    );

    await tester.tap(find.byTooltip('Delete Webhook'));
    await tester.pumpAndSettle();
    expect(find.textContaining('stops receiving runtime events'), findsOne);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.deleted, isEmpty);

    await tester.tap(find.byTooltip('Delete Webhook'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repository.deleted, <String>['wh_all']);
    expect(find.text('https://example.com/alera'), findsNothing);
    expect(find.text('No webhooks'), findsOneWidget);
  });

  testWidgets('sends a test event and reports it', (tester) async {
    final repository = await pump(
      tester,
      _FakeWebhookRepository(webhooks: <RuntimeWebhook>[_allEvents]),
    );

    await tester.tap(find.byTooltip('Send Test Event'));
    await tester.pumpAndSettle();

    expect(repository.tested, <String>['wh_all']);
    expect(find.textContaining('Test event queued'), findsOneWidget);
  });

  testWidgets('shows a failed test inline', (tester) async {
    await pump(
      tester,
      _FakeWebhookRepository(
        webhooks: <RuntimeWebhook>[_allEvents],
        testError: StateError('Webhook delivery is paused.'),
      ),
    );

    await tester.tap(find.byTooltip('Send Test Event'));
    await tester.pumpAndSettle();

    expect(find.text('Webhook delivery is paused.'), findsOneWidget);
  });

  test('registers a searchable Webhooks group in MCP Access', () {
    final section = mcpAccessSettingsSection(
      paneKeys: (_, groups) => <String, GlobalKey>{
        for (final group in groups) group.id: GlobalKey(),
      },
    );

    expect(section.groups.map((group) => group.id), contains('webhooks'));
    expect(section.firstMatchingGroupId('webhook'), 'webhooks');
    expect(section.firstMatchingGroupId('signing secret'), 'webhooks');
  });
}

final class _FakeWebhookRepository implements WebhookRepository {
  _FakeWebhookRepository({
    this.supported = true,
    List<RuntimeWebhook> webhooks = const <RuntimeWebhook>[],
    this.listError,
    this.createError,
    this.testError,
  }) : _webhooks = List<RuntimeWebhook>.of(webhooks);

  final bool supported;
  final List<RuntimeWebhook> _webhooks;
  final Object? listError;
  final Object? createError;
  final Object? testError;
  int listCalls = 0;

  /// When set, creation waits for it, like a slow cloud answer.
  Completer<void>? createGate;
  final List<(String, List<String>?)> created = <(String, List<String>?)>[];
  final List<String> deleted = <String>[];
  final List<String> tested = <String>[];

  @override
  Future<bool> supportsWebhooks() async => supported;

  @override
  Future<List<RuntimeWebhook>> listWebhooks() async {
    listCalls += 1;
    if (listError case final Object error) {
      throw error;
    }
    return List<RuntimeWebhook>.of(_webhooks);
  }

  @override
  Future<RuntimeWebhookCreation> createWebhook({
    required String url,
    List<String>? kinds,
  }) async {
    created.add((url, kinds));
    await createGate?.future;
    if (createError case final Object error) {
      throw error;
    }
    final webhook = RuntimeWebhook(
      id: 'wh_${created.length}',
      url: url,
      kinds:
          kinds ??
          <String>[for (final kind in RuntimeEventKind.values) kind.wireName],
      status: 'active',
    );
    _webhooks.add(webhook);
    return RuntimeWebhookCreation(webhook: webhook, secret: 'whsec_once');
  }

  @override
  Future<void> deleteWebhook(String id) async {
    deleted.add(id);
    _webhooks.removeWhere((webhook) => webhook.id == id);
  }

  @override
  Future<String> testWebhook(String id) async {
    tested.add(id);
    if (testError case final Object error) {
      throw error;
    }
    return 'dl_1';
  }
}

final class _FakeMcpAccessRepository implements McpAccessRepository {
  _FakeMcpAccessRepository({required this.accountConnected});

  final bool accountConnected;

  McpAccessSettings get _settings => McpAccessSettings(
    access: McpAccessLevel.off,
    effectiveRuntimeName: 'studio-box',
    accountConnected: accountConnected,
  );

  @override
  Stream<McpAccessSettings?> watchSettings() {
    return Stream<McpAccessSettings?>.value(_settings);
  }

  @override
  Future<McpAccessSettings> updateSettings({
    McpAccessLevel? access,
    String? runtimeName,
  }) async => _settings;

  @override
  Future<List<McpGrant>> listGrants() async => const <McpGrant>[];

  @override
  Future<void> revokeGrant(String grantId) async {}
}
