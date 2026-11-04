import 'dart:async';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_full_data.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_item_details.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _chat = AgentChatRef(chatId: 'chat', workspaceId: 'workspace');
const _payloadRef = <String, Object?>{
  'itemId': 'tool:payload:1',
  'segmentCount': 2,
  'format': 'json',
};

AgentChatItem _item({
  Map<String, Object?> normalized = const <String, Object?>{
    'payloadRef': _payloadRef,
  },
  Map<String, Object?> data = const <String, Object?>{},
  DateTime? updatedAt,
}) => AgentChatItem(
  id: 'tool',
  type: AgentChatItemType.mcpToolCall,
  status: AgentChatItemStatus.completed,
  createdAt: DateTime.utc(2026, 10, 12),
  updatedAt: updatedAt ?? DateTime.utc(2026, 10, 12),
  toolName: 'lookup',
  normalized: normalized,
  data: data,
);

/// Serves each payload request from [respond], one page per chunk.
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

Map<String, Object?> _page(List<String> parts, int index) => <String, Object?>{
  'chunks': <Map<String, Object?>>[
    <String, Object?>{'index': index, 'text': parts[index]},
  ],
  'segmentCount': parts.length,
  'revision': '1',
  'format': 'json',
  if (index + 1 < parts.length) 'nextIndex': index + 1,
};

void _serve(_Transport transport, List<String> parts) =>
    transport.respond = (request) async =>
        _page(parts, request['index']! as int);

Future<void> _pump(
  WidgetTester tester,
  _Transport transport,
  AgentChatItem item,
) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      agentChatRepositoryProvider.overrideWithValue(
        RuntimeAgentChatRepository(transport),
      ),
    ],
    child: MaterialApp(
      theme: buildAleraDarkTheme(),
      home: Scaffold(
        body: AgentChatFullDataScope(
          chat: _chat,
          child: SingleChildScrollView(
            child: AgentChatItemDetails(item: item, onOpenFile: (_) {}),
          ),
        ),
      ),
    ),
  ),
);

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

  testWidgets('items without a payload reference keep Show Raw Data', (
    tester,
  ) async {
    final transport = _Transport();
    await _pump(
      tester,
      transport,
      _item(
        normalized: const <String, Object?>{},
        data: const <String, Object?>{'raw': true},
      ),
    );
    expect(find.text('Load Full Data'), findsNothing);
    expect(find.text('Show Raw Data'), findsOneWidget);
    expect(transport.requests, isEmpty);
  });

  testWidgets('loads exact text only on request and copies all of it', (
    tester,
  ) async {
    const parts = <String>['{"nested":"🧪', r'\n", "spaced" : [1, true]}'];
    final transport = _Transport();
    _serve(transport, parts);
    await _pump(
      tester,
      transport,
      _item(data: const <String, Object?>{'raw': true}),
    );
    expect(find.text('Show Raw Data'), findsNothing);
    expect(transport.requests, isEmpty);

    await tester.tap(find.text('Load Full Data'));
    await tester.pumpAndSettle();

    expect(transport.requests.map((request) => request['itemId']), <String>[
      'tool',
      'tool',
    ]);
    final full = parts.join();
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      full,
    );
    expect(find.text('${full.length} characters'), findsOneWidget);

    await tester.tap(find.text('Copy Full Data'));
    await tester.pump();
    expect(copied, <String>[full]);
  });

  testWidgets('previews a bounded head and still copies everything', (
    tester,
  ) async {
    final full = '[${List<String>.filled(30000, '1').join(',')}]';
    final transport = _Transport();
    _serve(transport, <String>[full]);
    await _pump(tester, transport, _item());

    await tester.tap(find.text('Load Full Data'));
    await tester.pumpAndSettle();

    final preview = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(preview.data, full.substring(0, 20000));
    expect(find.text('First 20,000 of 60,001 characters'), findsOneWidget);
    await tester.tap(find.text('Copy Full Data'));
    await tester.pump();
    expect(copied.single, full);
  });

  testWidgets('a failed load shows why and retries', (tester) async {
    final transport = _Transport()
      ..respond = (_) async => throw const AgentChatRequestException(
        code: 'invalid',
        message: 'item has no payload reference',
      );
    await _pump(tester, transport, _item());

    await tester.tap(find.text('Load Full Data'));
    await tester.pumpAndSettle();
    expect(find.text('item has no payload reference'), findsOneWidget);

    _serve(transport, <String>['{}']);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('item has no payload reference'), findsNothing);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      '{}',
    );
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
    pending.complete(_page(<String>['{"old":true}'], 0));
    await tester.pumpAndSettle();

    expect(find.byType(SelectableText), findsNothing);
    expect(_loadButton(tester).onPressed, isNotNull);
  });

  test('preview never ends inside a surrogate pair', () {
    expect(agentChatFullDataPreview('ab🧪', 3), 'ab');
    expect(agentChatFullDataPreview('ab🧪', 4), 'ab🧪');
    expect(
      agentChatFullDataCaption(5, 1234567),
      'First 5 of 1,234,567 characters',
    );
  });

  test('malformed pages read as incomplete data', () {
    expect(
      agentChatFullDataErrorMessage(const FormatException('changed')),
      'The runtime returned incomplete data.',
    );
    expect(
      agentChatFullDataErrorMessage(StateError('boom')),
      'Could not load the full data.',
    );
  });
}
