import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_full_data.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_tool_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AgentChatItem _item({
  Map<String, Object?> normalized = const <String, Object?>{
    'payloadRef': <String, Object?>{'field': 'data', 'format': 'json'},
  },
  DateTime? updatedAt,
}) => AgentChatItem(
  id: 'tool',
  type: AgentChatItemType.mcpToolCall,
  status: AgentChatItemStatus.completed,
  createdAt: DateTime.utc(2026, 10, 12),
  updatedAt: updatedAt ?? DateTime.utc(2026, 10, 12),
  toolName: 'lookup',
  input: 'preview…',
  normalized: normalized,
);

final class _Transport implements AgentChatTransport {
  final requests = <Map<String, Object?>>[];
  late Future<Map<String, Object?>> Function(Map<String, Object?>) respond;

  @override
  Stream<AgentChatTransportEvent> get events => const Stream.empty();

  @override
  Future<bool> supportsCapability(String capability) async => true;

  @override
  Future<Map<String, Object?>> request(
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) {
    requests.add(payload);
    return respond(payload);
  }
}

Map<String, Object?> _page(String text) => <String, Object?>{
  'chunks': <Map<String, Object?>>[
    <String, Object?>{'index': 0, 'text': text},
  ],
  'segmentCount': 1,
  'revision': '1',
  'format': 'json',
};

Future<void> _pump(
  WidgetTester tester,
  _Transport transport,
  AgentChatItem item,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentChatRepositoryProvider('host')
            .overrideWith((ref) async => RuntimeAgentChatRepository(transport)),
      ],
      child: MaterialApp(
        theme: buildAleraMobileDarkTheme(),
        home: Scaffold(
          body: AgentChatScope(
            hostId: 'host',
            workspaceId: 'workspace',
            chatId: 'chat',
            cwd: null,
            child: SingleChildScrollView(
              child: AgentChatToolDetails(item: item),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

TextButton _loadButton(WidgetTester tester) => tester.widget<TextButton>(
  find.byWidgetPredicate((widget) => widget is TextButton),
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final copied = <String>[];
  setUp(() {
    copied.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  testWidgets('no payload reference offers no load', (tester) async {
    final transport = _Transport();
    await _pump(
      tester,
      transport,
      _item(normalized: const <String, Object?>{}),
    );
    expect(find.text('Load Full Data'), findsNothing);
    expect(transport.requests, isEmpty);
  });

  testWidgets('loads exact text on request, bounds it and copies all of it', (
    tester,
  ) async {
    final full = '{"values":[${List<String>.filled(8000, '"🧪"').join(',')}]}';
    final transport = _Transport()..respond = (_) async => _page(full);
    await _pump(tester, transport, _item());
    expect(transport.requests, isEmpty);

    await tester.tap(find.text('Load Full Data'));
    await tester.pumpAndSettle();

    expect(transport.requests.single['itemId'], 'tool');
    final preview = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .last
        .data!;
    expect(preview.length, lessThanOrEqualTo(12000));
    expect(full.startsWith(preview), isTrue);
    expect(find.textContaining('First '), findsOneWidget);

    await tester.tap(find.text('Copy Full Data'));
    await tester.pump();
    expect(copied, <String>[full]);
    expect(find.text('Full data copied'), findsOneWidget);
  });

  testWidgets('a failed load shows why and retries', (tester) async {
    final transport = _Transport()
      ..respond = (_) async =>
          throw const AgentChatConnectionException('closed');
    await _pump(tester, transport, _item());

    await tester.tap(find.text('Load Full Data'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not reachable'), findsOneWidget);

    transport.respond = (_) async => _page('{}');
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not reachable'), findsNothing);
    expect(find.text('2 characters'), findsOneWidget);
  });

  testWidgets('a changed item starts over and drops a stale load', (
    tester,
  ) async {
    final pending = Completer<Map<String, Object?>>();
    final transport = _Transport()..respond = (_) => pending.future;
    await _pump(tester, transport, _item());

    await tester.tap(find.text('Load Full Data'));
    await tester.pump();
    expect(_loadButton(tester).onPressed, isNull);

    await _pump(
      tester,
      transport,
      _item(updatedAt: DateTime.utc(2026, 10, 13)),
    );
    pending.complete(_page('{"old":true}'));
    await tester.pumpAndSettle();

    expect(find.text('Copy Full Data'), findsNothing);
    expect(_loadButton(tester).onPressed, isNotNull);
  });

  test('preview never ends inside a surrogate pair', () {
    expect(agentChatFullDataPreview('ab🧪', 3), 'ab');
    expect(
      agentChatFullDataCaption(12000, 1234567),
      'First 12,000 of 1,234,567 characters',
    );
  });
}
