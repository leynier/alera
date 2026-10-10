import 'dart:async';

import 'package:alera/src/features/mcp_access/domain/mcp_access_error_message.dart';
import 'package:alera/src/features/mcp_access/domain/mcp_access_settings.dart';
import 'package:alera/src/features/mcp_access/domain/mcp_grant.dart';
import 'package:alera/src/features/mcp_access/infra/runtime_mcp_access_repository.dart';
import 'package:alera/src/features/mcp_access/presentation/mcp_connected_apps_group.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _settings({
  String access = 'read',
  String? runtimeName = 'Studio',
  String effectiveRuntimeName = 'Studio',
  bool accountConnected = true,
}) {
  return <String, Object?>{
    'access': access,
    'runtimeName': runtimeName,
    'effectiveRuntimeName': effectiveRuntimeName,
    'accountConnected': accountConnected,
    'relay': <String, Object?>{'state': 'retrying', 'lastError': 'timed out'},
  };
}

void main() {
  test('parses settings, including unknown values, safely', () {
    final settings = McpAccessSettings.fromJson(_settings(runtimeName: null));
    expect(settings.access, McpAccessLevel.read);
    expect(settings.runtimeName, isNull);
    expect(settings.effectiveRuntimeName, 'Studio');
    expect(settings.accountConnected, isTrue);
    expect(settings.relay.state, McpRelayState.retrying);
    expect(settings.relay.lastError, 'timed out');

    final fallback = McpAccessSettings.fromJson(<String, Object?>{
      'access': 'everything',
      'effectiveRuntimeName': 'box',
    });
    expect(fallback.access, McpAccessLevel.off);
    expect(fallback.accountConnected, isFalse);
    expect(fallback.relay.state, McpRelayState.unknown);
    expect(
      () => McpAccessSettings.fromJson(const <String, Object?>{}),
      throwsFormatException,
    );
  });

  test('reads every access level and orders admin last', () {
    for (final (wire, level) in <(String, McpAccessLevel)>[
      ('off', .off),
      ('read', .read),
      ('full', .full),
      ('admin', .admin),
    ]) {
      expect(McpAccessLevel.fromWire(wire), level);
      expect(level.wireName, wire);
    }
    expect(McpAccessLevel.values, <McpAccessLevel>[.off, .read, .full, .admin]);
    expect(McpAccessLevel.fromWire('ADMIN'), McpAccessLevel.off);
    expect(
      McpAccessSettings.fromJson(_settings(access: 'admin')).access,
      McpAccessLevel.admin,
    );
  });

  test('update sends the admin access level', () async {
    final client = _FakeRuntimeHostClient()
      ..responses['mcp.settings.update'] = _settings(access: 'admin');
    final repository = RuntimeMcpAccessRepository(client);

    final updated = await repository.updateSettings(access: .admin);

    expect(updated.access, McpAccessLevel.admin);
    expect(client.calls.single.payload, <String, Object?>{'access': 'admin'});
  });

  test('update sends only the fields that are set', () async {
    final client = _FakeRuntimeHostClient()
      ..responses['mcp.settings.update'] = _settings(access: 'full');
    final repository = RuntimeMcpAccessRepository(client);

    final updated = await repository.updateSettings(access: .full);
    await repository.updateSettings(runtimeName: 'Laptop');

    expect(updated.access, McpAccessLevel.full);
    expect(client.calls.map((call) => call.payload), <Map<String, Object?>>[
      <String, Object?>{'access': 'full'},
      <String, Object?>{'runtimeName': 'Laptop'},
    ]);
  });

  test('lists grants and revokes one by id', () async {
    final client = _FakeRuntimeHostClient()
      ..responses['mcp.grants.list'] = <String, Object?>{
        'grants': <Object?>[
          <String, Object?>{
            'id': 'grant-1',
            'clientId': 'https://claude.ai/oauth/client.json',
            'clientName': 'Claude',
            'redirectHost': 'claude.ai',
            'scopes': <String>['mcp:read', 'mcp:execute'],
            'allRuntimes': false,
            'runtimeIds': <String>['runtime-1', 'runtime-2'],
            'createdAt': '2026-10-01T10:00:00Z',
            'lastUsedAt': null,
          },
          'not a grant',
        ],
      }
      ..responses['mcp.grants.revoke'] = <String, Object?>{'revoked': true};
    final repository = RuntimeMcpAccessRepository(client);

    final grants = await repository.listGrants();
    await repository.revokeGrant('grant-1');

    expect(grants, hasLength(1));
    final grant = grants.single;
    expect(grant.clientName, 'Claude');
    expect(grant.canExecute, isTrue);
    expect(grant.canAdmin, isFalse);
    expect(grant.createdAt, DateTime.utc(2026, 10, 1, 10));
    expect(grant.lastUsedAt, isNull);
    expect(mcpGrantDetail(grant), 'claude.ai · 2 runtimes · Never used');
    expect(client.calls.last.type, 'mcp.grants.revoke');
    expect(client.calls.last.payload, <String, Object?>{'grantId': 'grant-1'});
  });

  test('reads the admin scope of a grant', () {
    final grant = McpGrant.fromJson(<String, Object?>{
      'id': 'grant-3',
      'clientId': 'admin-client',
      'scopes': <String>['mcp:read', 'mcp:execute', 'mcp:admin'],
    });
    expect(grant.canExecute, isTrue);
    expect(grant.canAdmin, isTrue);
  });

  test('describes a grant that reaches every runtime', () {
    final grant = McpGrant.fromJson(<String, Object?>{
      'id': 'grant-2',
      'clientId': 'chatgpt',
      'scopes': <String>['mcp:read'],
      'allRuntimes': true,
    });
    expect(grant.clientName, 'chatgpt');
    expect(grant.canExecute, isFalse);
    expect(grant.canAdmin, isFalse);
    expect(mcpGrantDetail(grant), 'All runtimes · Never used');
  });

  test('reports an older runtime as unsupported instead of retrying', () async {
    final client = _FakeRuntimeHostClient()..unknownRequests = true;
    final repository = RuntimeMcpAccessRepository(client);

    expect(await repository.watchSettings().first, isNull);
  });

  test('refreshes settings on mcpSettingsChanged', () async {
    final client = _FakeRuntimeHostClient()
      ..responses['mcp.settings.get'] = _settings(access: 'off');
    final repository = RuntimeMcpAccessRepository(
      client,
      coalescer: RuntimeChangeCoalescer(
        debounce: const Duration(milliseconds: 1),
        maxDelay: const Duration(milliseconds: 5),
      ),
    );
    final values = <McpAccessLevel?>[];
    final sub = repository.watchSettings().listen(
      (settings) => values.add(settings?.access),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    client.responses['mcp.settings.get'] = _settings(access: 'full');
    client.emit(
      const RuntimeHostEvent('mcpSettingsChanged', <String, Object?>{}),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await sub.cancel();

    expect(values, <McpAccessLevel?>[McpAccessLevel.off, McpAccessLevel.full]);
    expect(runtimeHostEventNames, contains('mcpSettingsChanged'));
  });

  test('maps runtime errors to sentence-case messages', () {
    expect(
      mcpAccessErrorMessage(
        const TerminalHostConflictException(
          code: 'runtime_name_taken',
          message: 'runtime_name_taken',
        ),
      ),
      'Another runtime in your Alera account already uses this name.',
    );
    expect(
      mcpAccessErrorMessage(
        StateError('Unknown terminal host request: mcp.grants.list'),
      ),
      'Update the Alera runtime to use MCP Control.',
    );
    expect(
      mcpAccessErrorMessage(StateError('Sign in to an Alera account first.')),
      'Sign in to an Alera account first.',
    );
    expect(
      mcpAccessErrorMessage(const TerminalHostConnectionClosedException()),
      'The Alera runtime is not reachable.',
    );
    expect(
      mcpAccessErrorMessage(
        const TerminalHostConflictException(
          code: 'mcp_cloud_error',
          message: 'The Alera cloud refused the request.',
        ),
      ),
      'The Alera cloud refused the request.',
    );
    expect(
      mcpAccessErrorMessage(const FormatException('Bad payload.')),
      'Bad payload.',
    );
    expect(mcpAccessErrorMessage(42), '42');
  });

  test('reads every relay state and treats others as unknown', () {
    expect(
      <McpRelayState>[
        for (final state in <String>[
          'connected',
          'connecting',
          'retrying',
          'blocked',
          'disabled',
          'paused',
        ])
          McpRelayState.fromWire(state),
      ],
      <McpRelayState>[
        .connected,
        .connecting,
        .retrying,
        .blocked,
        .disabled,
        .unknown,
      ],
    );
  });

  test('accepts epoch timestamps in seconds and milliseconds', () {
    final grant = McpGrant.fromJson(<String, Object?>{
      'id': 'grant-3',
      'createdAt': 1790000000,
      'lastUsedAt': 1790000000000,
    });
    expect(grant.clientName, 'Unknown App');
    expect(grant.createdAt, grant.lastUsedAt);
    expect(grant.createdAt!.isUtc, isTrue);
    expect(
      () => McpGrant.fromJson(const <String, Object?>{'id': ''}),
      throwsFormatException,
    );
  });
}

final class _Call {
  _Call(this.type, this.payload);

  final String type;
  final Map<String, Object?> payload;
}

final class _FakeRuntimeHostClient implements RuntimeHostClient {
  final Map<String, Object?> responses = <String, Object?>{};
  final List<_Call> calls = <_Call>[];
  final StreamController<RuntimeHostEvent> _events =
      StreamController<RuntimeHostEvent>.broadcast();
  bool unknownRequests = false;

  void emit(RuntimeHostEvent event) => _events.add(event);

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    calls.add(_Call(type, Map<String, Object?>.from(payload)));
    if (unknownRequests) {
      throw StateError('Unknown terminal host request: $type');
    }
    return responses[type];
  }
}
