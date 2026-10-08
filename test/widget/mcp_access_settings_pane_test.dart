import 'dart:async';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/mcp_access/application/mcp_access_providers.dart';
import 'package:alera/src/features/mcp_access/domain/mcp_access_repository.dart';
import 'package:alera/src/features/mcp_access/domain/mcp_access_settings.dart';
import 'package:alera/src/features/mcp_access/domain/mcp_grant.dart';
import 'package:alera/src/features/mcp_access/presentation/mcp_access_settings_pane.dart';
import 'package:alera/src/features/settings/presentation/mcp_access_settings_section.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

McpAccessSettings _settings({
  McpAccessLevel access = McpAccessLevel.off,
  bool accountConnected = true,
  String? runtimeName,
  String effectiveRuntimeName = 'studio-box',
  McpRelayStatus relay = const McpRelayStatus(state: McpRelayState.connected),
}) {
  return McpAccessSettings(
    access: access,
    runtimeName: runtimeName,
    effectiveRuntimeName: effectiveRuntimeName,
    accountConnected: accountConnected,
    relay: relay,
  );
}

final McpGrant _claudeGrant = McpGrant(
  id: 'grant-claude',
  clientId: 'https://claude.ai/oauth/client.json',
  clientName: 'Claude',
  redirectHost: 'claude.ai',
  scopes: const <String>['mcp:read', 'mcp:execute'],
  allRuntimes: true,
  runtimeIds: const <String>[],
  lastUsedAt: DateTime.utc(2026, 10, 2, 9, 30),
);

const McpGrant _chatGptGrant = McpGrant(
  id: 'grant-chatgpt',
  clientId: 'chatgpt',
  clientName: 'ChatGPT',
  redirectHost: 'chatgpt.com',
  scopes: <String>['mcp:read'],
  allRuntimes: false,
  runtimeIds: <String>['runtime-1'],
);

void main() {
  Future<_FakeMcpAccessRepository> pumpPane(
    WidgetTester tester,
    _FakeMcpAccessRepository repository,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mcpAccessRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: aleraDarkTheme,
          home: const Scaffold(
            body: SingleChildScrollView(child: McpAccessSettingsPane()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  bool segmentEnabled(WidgetTester tester, String label) {
    final button = tester.widget<SegmentedButton<McpAccessLevel>>(
      find.byType(SegmentedButton<McpAccessLevel>),
    );
    return button.segments
        .firstWhere((segment) => (segment.label! as Text).data == label)
        .enabled;
  }

  for (final (level, description) in <(McpAccessLevel, String)>[
    (.off, 'MCP clients cannot reach this runtime.'),
    (.read, 'MCP clients can run read-only tools.'),
    (.full, 'MCP clients can run every Alera tool'),
  ]) {
    testWidgets('shows the ${level.name} access level', (tester) async {
      await pumpPane(
        tester,
        _FakeMcpAccessRepository(_settings(access: level)),
      );

      final button = tester.widget<SegmentedButton<McpAccessLevel>>(
        find.byType(SegmentedButton<McpAccessLevel>),
      );
      expect(button.selected, <McpAccessLevel>{level});
      expect(find.textContaining(description), findsOneWidget);
      expect(find.text('Off'), findsWidgets);
      expect(find.text('Read Only'), findsOneWidget);
      expect(find.text('Full Control'), findsOneWidget);
      expect(find.textContaining('not stored'), findsOneWidget);
      expect(find.text('https://api.alera.build/v1/mcp'), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);
    });
  }

  testWidgets('selecting an access level updates the runtime', (tester) async {
    final repository = await pumpPane(
      tester,
      _FakeMcpAccessRepository(_settings()),
    );

    await tester.tap(find.text('Full Control'));
    await tester.pumpAndSettle();

    expect(repository.updates, <(McpAccessLevel?, String?)>[(.full, null)]);
    final button = tester.widget<SegmentedButton<McpAccessLevel>>(
      find.byType(SegmentedButton<McpAccessLevel>),
    );
    expect(button.selected, <McpAccessLevel>{McpAccessLevel.full});
  });

  testWidgets('requires an Alera account before turning access on', (
    tester,
  ) async {
    final repository = await pumpPane(
      tester,
      _FakeMcpAccessRepository(
        _settings(
          accountConnected: false,
          relay: const McpRelayStatus(state: McpRelayState.disabled),
        ),
      ),
    );

    expect(segmentEnabled(tester, 'Off'), isTrue);
    expect(segmentEnabled(tester, 'Read Only'), isFalse);
    expect(segmentEnabled(tester, 'Full Control'), isFalse);
    expect(
      find.textContaining('Sign in to an Alera account in Settings > Account'),
      findsOneWidget,
    );
    expect(find.text('Not signed in'), findsOneWidget);
    expect(repository.grantReads, 0);
  });

  testWidgets('renames the runtime', (tester) async {
    final repository = await pumpPane(
      tester,
      _FakeMcpAccessRepository(_settings()),
    );
    expect(
      find.text('Currently "studio-box", taken from the host name.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'Laptop');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();

    expect(repository.updates, <(McpAccessLevel?, String?)>[(null, 'Laptop')]);
    expect(find.text('Currently "Laptop".'), findsOneWidget);
  });

  testWidgets('shows a rename failure inline', (tester) async {
    final repository = _FakeMcpAccessRepository(_settings())
      ..renameError = const TerminalHostConflictException(
        code: 'runtime_name_taken',
        message: 'runtime name taken',
      );
    await pumpPane(tester, repository);

    await tester.enterText(find.byType(TextField), 'Desktop');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Another runtime in your Alera account already uses this name.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Currently "studio-box", taken from the host name.'),
      findsOneWidget,
    );
  });

  testWidgets('lists connected apps', (tester) async {
    final repository = _FakeMcpAccessRepository(_settings())
      ..grants = <McpGrant>[_claudeGrant, _chatGptGrant];
    await pumpPane(tester, repository);

    expect(find.text('Claude'), findsOneWidget);
    expect(find.text('ChatGPT'), findsOneWidget);
    expect(find.text('mcp:execute'), findsOneWidget);
    expect(
      find.textContaining('claude.ai · All runtimes · Last used'),
      findsOneWidget,
    );
    expect(find.text('chatgpt.com · 1 runtime · Never used'), findsOneWidget);
    expect(repository.grantReads, 1);
  });

  testWidgets('shows an empty state without connected apps', (tester) async {
    await pumpPane(tester, _FakeMcpAccessRepository(_settings()));

    expect(find.text('No connected apps'), findsOneWidget);
  });

  testWidgets('revokes an app after confirmation', (tester) async {
    final repository = _FakeMcpAccessRepository(_settings())
      ..grants = <McpGrant>[_claudeGrant, _chatGptGrant];
    await pumpPane(tester, repository);

    await tester.tap(find.byTooltip('Revoke App').first);
    await tester.pumpAndSettle();
    expect(find.text('Revoke Claude'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Revoke'));
    await tester.pumpAndSettle();

    expect(repository.revoked, <String>['grant-claude']);
    expect(find.text('Claude'), findsNothing);
    expect(find.text('ChatGPT'), findsOneWidget);
    expect(repository.grantReads, 2);
  });

  testWidgets('cancelling the revoke dialog keeps the app', (tester) async {
    final repository = _FakeMcpAccessRepository(_settings())
      ..grants = <McpGrant>[_claudeGrant];
    await pumpPane(tester, repository);

    await tester.tap(find.byTooltip('Revoke App'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.revoked, isEmpty);
    expect(find.text('Claude'), findsOneWidget);
  });

  testWidgets('copies the MCP endpoint', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpPane(tester, _FakeMcpAccessRepository(_settings()));

    await tester.tap(find.byTooltip('Copy Endpoint'));
    await tester.pumpAndSettle();

    expect(copied, 'https://api.alera.build/v1/mcp');
    expect(find.byTooltip('Copied'), findsOneWidget);
  });

  testWidgets('explains a relay error', (tester) async {
    await pumpPane(
      tester,
      _FakeMcpAccessRepository(
        _settings(
          access: .read,
          relay: const McpRelayStatus(
            state: McpRelayState.retrying,
            lastError: 'connection refused',
          ),
        ),
      ),
    );

    expect(find.text('Error'), findsOneWidget);
    expect(
      find.textContaining('Last error: connection refused'),
      findsOneWidget,
    );
  });

  test('registers a searchable MCP Access settings section', () {
    final section = mcpAccessSettingsSection(
      paneKeys: (_, groups) => <String, GlobalKey>{
        for (final group in groups) group.id: GlobalKey(),
      },
    );

    expect(section.id, 'mcpAccess');
    expect(section.title, 'MCP Access');
    expect(section.matches('chatgpt'), isTrue);
    expect(section.firstMatchingGroupId('revoke'), 'apps');
    expect(section.firstMatchingGroupId('rename'), 'runtime');
  });

  testWidgets('asks to update an older runtime', (tester) async {
    await pumpPane(tester, _FakeMcpAccessRepository(null));

    expect(
      find.text('Update the Alera runtime to use MCP Control.'),
      findsOneWidget,
    );
  });
}

final class _FakeMcpAccessRepository implements McpAccessRepository {
  _FakeMcpAccessRepository(this._settings);

  McpAccessSettings? _settings;
  List<McpGrant> grants = <McpGrant>[];
  Object? renameError;
  int grantReads = 0;
  final List<(McpAccessLevel?, String?)> updates =
      <(McpAccessLevel?, String?)>[];
  final List<String> revoked = <String>[];

  @override
  Stream<McpAccessSettings?> watchSettings() {
    return Stream<McpAccessSettings?>.value(_settings);
  }

  @override
  Future<McpAccessSettings> updateSettings({
    McpAccessLevel? access,
    String? runtimeName,
  }) async {
    updates.add((access, runtimeName));
    if (runtimeName != null && renameError != null) {
      throw renameError!;
    }
    final current = _settings!;
    final next = McpAccessSettings(
      access: access ?? current.access,
      runtimeName: runtimeName ?? current.runtimeName,
      effectiveRuntimeName: runtimeName ?? current.effectiveRuntimeName,
      accountConnected: current.accountConnected,
      relay: current.relay,
    );
    _settings = next;
    return next;
  }

  @override
  Future<List<McpGrant>> listGrants() async {
    grantReads += 1;
    return List<McpGrant>.of(grants);
  }

  @override
  Future<void> revokeGrant(String grantId) async {
    revoked.add(grantId);
    grants = <McpGrant>[
      for (final grant in grants)
        if (grant.id != grantId) grant,
    ];
  }
}
