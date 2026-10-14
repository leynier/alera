/// Native frame-cost and cadence measurement for synthetic agent chat output.
///
/// Run explicitly on a device; the filename excludes this from `*_test.dart`
/// CI discovery. Compare the same SDK, build mode, device and window size.
/// Uses the shared projection and production message/entry widgets, without
/// providers, runtime initialization, credentials or network traffic.
library;

import 'dart:convert';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_shimmer_text.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_message_views.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_context.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_entry.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'agent_chat_benchmark_binding.dart';
import 'agent_chat_benchmark_diagnostics.dart';
import 'agent_chat_benchmark_service.dart';

const _duration = Duration(seconds: 8);
const _updateInterval = Duration(milliseconds: 50);
const _timingsDrain = Duration(seconds: 2);
const _historyTurnCount = 160;
const _liveTurnId = 'benchmark-live';
const _liveAnswerKey = ValueKey<String>('benchmark-live-answer');
const _viewportKey = ValueKey<String>('benchmark-chat-viewport');
const _endMarker = 'CHAT-BENCHMARK-END';

void _ignoreString(String _) {}
void _ignoreAction() {}

const _actions = AgentChatTimelineActions(
  chatId: 'benchmark-chat',
  onRetrySend: _ignoreString,
  onEditSend: _ignoreString,
  onOpenLink: _ignoreString,
  onOpenFile: _ignoreString,
  onImplementPlan: _ignoreAction,
);

void main() {
  final binding = AgentChatBenchmarkBinding();
  final recorder = _FrameRecorder(binding);
  // Observes naturally scheduled frames; this callback never requests one.
  binding.addPersistentFrameCallback((_) => recorder.observeFrame());

  testWidgets('agent chat streaming, long history and idle frame cadence', (
    tester,
  ) async {
    captureAgentChatBenchmarkFailures(binding);
    // Register synchronously before the standalone runner builds its suite.
    await tester.runAsync(writeAgentChatBenchmarkServiceInfo);
    final reports = <_Report>[];
    for (final historyCount in <int>[0, _historyTurnCount]) {
      final fixture = _Fixture(historyCount);
      try {
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: aleraDarkTheme,
            home: Scaffold(
              body: AleraShimmerScope(
                child: SelectionArea(
                  child: _BenchmarkTimeline(projection: fixture.projection),
                ),
              ),
            ),
          ),
        );
        // Warm fonts, Markdown parsing and complete/open code fences before
        // measuring. No pumps occur during warm-up or any measured window.
        await tester.runAsync(() async {
          for (var index = 0; index < 20; index += 1) {
            fixture.append();
            await Future.pause(_updateInterval);
          }
          await Future.pause(_timingsDrain);
        });
        final viewport = tester.getSize(find.byKey(_viewportKey));
        final stream = await recorder.measure(
          tester,
          fixture,
          viewport,
          scenario: historyCount == 0 ? 'stream' : 'history-and-stream',
          streaming: true,
        );
        reports.add(stream);
        expect(stream.updates, greaterThan(0));
        expect(stream.timings, isNotEmpty, reason: 'no native frames observed');
        _verifyContent(tester, fixture);

        if (historyCount == _historyTurnCount) {
          // A paused producer can still repaint the real Writing shimmer.
          reports.add(
            await recorder.measure(
              tester,
              fixture,
              viewport,
              scenario: 'history-live-idle',
              streaming: false,
            ),
          );
        }
        fixture.complete();
        await tester.runAsync(() => Future.pause(_timingsDrain));
        _verifyContent(tester, fixture);
        final end = find.textContaining(_endMarker, findRichText: true);
        expect(end, findsOneWidget, reason: 'final Markdown was not rendered');
        expect(
          tester
              .getRect(end)
              .overlaps(tester.getRect(find.byKey(_viewportKey))),
          isTrue,
          reason: 'the latest output is outside the viewport',
        );
        if (historyCount == _historyTurnCount) {
          reports.add(
            await recorder.measure(
              tester,
              fixture,
              viewport,
              scenario: 'history-completed-idle',
              streaming: false,
            ),
          );
          _verifyContent(tester, fixture);
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.projection.dispose();
      }
    }
    final data = <String, Object?>{
      'platform': defaultTargetPlatform.name,
      'build_mode': kProfileMode
          ? 'profile'
          : kReleaseMode
          ? 'release'
          : 'debug',
      'device_pixel_ratio': tester.view.devicePixelRatio,
      'update_interval_ms': _updateInterval.inMilliseconds,
      'reports': reports.map((report) => report.toJson()).toList(),
    };
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['agent_chat_render_benchmark'] = data;
    // ignore: avoid_print
    print('\n=== agent chat render benchmark ===');
    for (final report in reports) {
      // ignore: avoid_print
      print(report);
    }
    // ignore: avoid_print
    print('AGENT_CHAT_BENCHMARK_JSON ${jsonEncode(data)}');
  });
}

void _verifyContent(WidgetTester tester, _Fixture fixture) {
  final projection = fixture.projection.value;
  expect(projection.entries.length, fixture.historyCount + 1);
  expect(
    <String>[
      for (final entry in projection.entries)
        if (entry is AgentChatTurnEntry)
          for (final item in entry.section.sourceItems) item.id,
    ],
    orderedEquals(fixture.items.map((item) => item.id)),
    reason: 'canonical history or live items were dropped by projection',
  );
  for (final item in fixture.historyItems) {
    final section = projection.sectionFor(item.turnId!)!;
    expect(
      section.sourceItems.firstWhere((source) => source.id == item.id),
      same(item),
    );
  }
  expect(projection.sectionFor(_liveTurnId)!.answers.single.text, fixture.text);
  final markdown = find.descendant(
    of: find.byKey(_liveAnswerKey),
    matching: find.byType(AgentChatMarkdown),
  );
  expect(markdown, findsOneWidget);
  expect(tester.widget<AgentChatMarkdown>(markdown).data, fixture.text);
}

final class _Fixture {
  _Fixture(this.historyCount) {
    for (var index = 0; index < historyCount; index += 1) {
      final id = 'history-$index';
      historyTurns.add(AgentChatTurn(id: id, status: .completed));
      historyItems.addAll(<AgentChatItem>[
        _item('$id-user', id, .userMessage, 'Explain completed change $index.'),
        _item('$id-answer', id, .assistantMessage, _chunk(index * 6)),
      ]);
    }
    _publish();
  }

  final int historyCount;
  final historyTurns = <AgentChatTurn>[];
  final historyItems = <AgentChatItem>[];
  final projection = ValueNotifier<AgentChatTimelineProjection>(
    AgentChatTimelineProjection.build(
      AgentChatThread.fromSnapshot(
        const AgentChatSnapshot(
          chatId: 'benchmark-chat',
          workspaceId: '',
          cursor: 0,
        ),
      ),
    ),
  );
  final DateTime _createdAt = DateTime.utc(2026, 10, 13);
  String text = '## Synthetic Assistant Output\n\n';
  int updates = 0;
  bool completed = false;
  List<AgentChatItem> items = const <AgentChatItem>[];

  AgentChatItem _item(
    String id,
    String turnId,
    AgentChatItemType type,
    String text, {
    bool streaming = false,
  }) => AgentChatItem(
    id: id,
    turnId: turnId,
    type: type,
    status: streaming ? .inProgress : .completed,
    streaming: streaming,
    createdAt: _createdAt,
    updatedAt: _createdAt.add(_updateInterval * updates),
    text: text,
  );

  void append() {
    text += _chunk(updates++);
    _publish();
  }

  void complete() {
    if ((updates - 1) % 6 case 3 || 4) text += '\n```\n';
    text += '\n\n$_endMarker\n';
    completed = true;
    _publish();
  }

  void _publish() {
    items = <AgentChatItem>[
      ...historyItems,
      _item(
        'live-user',
        _liveTurnId,
        .userMessage,
        'Describe the implementation.',
      ),
      _item(
        'live-answer',
        _liveTurnId,
        .assistantMessage,
        text,
        streaming: !completed,
      ),
    ];
    final thread = AgentChatThread.fromSnapshot(
      AgentChatSnapshot(
        chatId: 'benchmark-chat',
        workspaceId: 'benchmark-workspace',
        cursor: updates,
        session: AgentChatSession(
          status: completed ? .ready : .running,
          activeTurnId: completed ? null : _liveTurnId,
        ),
        turns: <AgentChatTurn>[
          ...historyTurns,
          AgentChatTurn(
            id: _liveTurnId,
            status: completed ? .completed : .running,
          ),
        ],
        items: items,
      ),
    );
    projection.value = AgentChatTimelineProjection.build(
      thread,
      previous: projection.value,
    );
  }
}

String _chunk(int index) => switch (index % 6) {
  0 =>
    '\n### Change $index\n\nThe **shared timeline** preserves `item-$index` while incremental Markdown grows. This paragraph wraps at the normal conversation width.\n\n',
  1 =>
    '- Preserve completed history.\n- Render update $index with *inline emphasis*.\n\n',
  2 =>
    '| Field | Value |\n| --- | --- |\n| Update | $index |\n| State | Streaming |\n\n',
  3 => '```dart\nfinal update$index = <String>[\n',
  4 => "  'canonical-item-$index',\n  'retained-content',\n];\n",
  _ => '```\n\nUpdate $index is retained in order.\n\n',
};

class const _BenchmarkTimeline({
  required final ValueListenable<AgentChatTimelineProjection> projection,
}) extends StatefulWidget {
  @override
  State<_BenchmarkTimeline> createState() => _BenchmarkTimelineState();
}

class _BenchmarkTimelineState extends State<_BenchmarkTimeline> {
  final _expansion = AgentChatExpansion();
  final _cache = <String, (Object, Widget)>{};

  Widget _row(AgentChatTimelineEntry entry) {
    final token = entry is AgentChatTurnEntry ? entry.section : entry;
    final cached = _cache[entry.key];
    if (cached != null && identical(cached.$1, token)) return cached.$2;
    final Widget content;
    if (entry case AgentChatTurnEntry(:final section)
        when section.turnId == _liveTurnId) {
      // The live header and scrolling coordinator read Riverpod. Use their
      // production presentational rows to keep this rendering boundary pure.
      content = Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          for (final prompt in section.prompts)
            AgentChatUserMessageView(
              chatId: _actions.chatId,
              item: prompt,
              workspacePath: '',
              onOpenFile: _ignoreString,
              expansion: _expansion,
            ),
          for (final answer in section.answers)
            AgentChatAssistantMessageView(
              key: _liveAnswerKey,
              item: answer,
              onOpenLink: _ignoreString,
            ),
        ],
      );
    } else {
      content = AgentChatTimelineEntryView(
        entry: entry,
        actions: _actions,
        expansion: _expansion,
        workspacePath: '',
      );
    }
    final row = Center(
      key: ValueKey<String>(entry.key),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AleraTokens.agentChatConversationMaxWidth,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space16),
          child: SizedBox(width: double.infinity, child: content),
        ),
      ),
    );
    _cache[entry.key] = (token, row);
    return row;
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<AgentChatTimelineProjection>(
    valueListenable: widget.projection,
    builder: (context, projection, _) => ListView.builder(
      key: _viewportKey,
      // Offset zero keeps the growing answer's end visible without a pump or
      // a scroll animation on every update. History remains lazily rendered.
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space24),
      itemCount: projection.entries.length,
      itemBuilder: (context, index) =>
          _row(projection.entries[projection.entries.length - 1 - index]),
    ),
  );
}

final class _FrameRecorder(final IntegrationTestWidgetsFlutterBinding binding) {
  Set<int>? _activeFrameNumbers;

  void observeFrame() => _activeFrameNumbers?.add(
    binding.platformDispatcher.frameData.frameNumber,
  );

  Future<_Report> measure(
    WidgetTester tester,
    _Fixture fixture,
    Size viewport, {
    required String scenario,
    required bool streaming,
  }) async {
    final frameNumbers = <int>{};
    final timings = <FrameTiming>[];
    void collect(List<FrameTiming> frames) => timings.addAll(frames);
    final beforeUpdates = fixture.updates;
    final beforeCharacters = fixture.text.length;
    final watch = Stopwatch();
    binding.addTimingsCallback(collect);
    try {
      _activeFrameNumbers = frameNumbers;
      watch.start();
      await tester.runAsync(() async {
        while (watch.elapsed < _duration) {
          if (streaming) fixture.append();
          await Future.pause(
            streaming ? _updateInterval : _duration - watch.elapsed,
          );
        }
      });
      watch.stop();
      _activeFrameNumbers = null;
      // Engine timings are batched; match their IDs to observed draw frames.
      await tester.runAsync(() => Future.pause(_timingsDrain));
      return _Report(
        scenario: scenario,
        elapsed: watch.elapsed,
        updates: fixture.updates - beforeUpdates,
        characters: fixture.text.length - beforeCharacters,
        totalCharacters: fixture.text.length,
        historyTurns: fixture.historyCount,
        viewport: viewport,
        frameworkFrames: frameNumbers.length,
        timings: List<FrameTiming>.unmodifiableOf(
          timings.where((frame) => frameNumbers.contains(frame.frameNumber)),
        ),
      );
    } finally {
      watch.stop();
      _activeFrameNumbers = null;
      binding.removeTimingsCallback(collect);
    }
  }
}

final class _Report({
  required final String scenario,
  required final Duration elapsed,
  required final int updates,
  required final int characters,
  required final int totalCharacters,
  required final int historyTurns,
  required final Size viewport,
  required final int frameworkFrames,
  required final List<FrameTiming> timings,
}) {
  double? _percentile(Duration Function(FrameTiming) select, double fraction) {
    final values =
        timings.map((frame) => select(frame).inMicroseconds / 1000).toList()
          ..sort();
    return values.isEmpty
        ? null
        : values[((values.length - 1) * fraction).round()];
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'scenario': scenario,
    'elapsed_ms': elapsed.inMicroseconds / 1000,
    'updates': updates,
    'characters_appended': characters,
    'total_characters': totalCharacters,
    'history_turns': historyTurns,
    'viewport_width': viewport.width,
    'viewport_height': viewport.height,
    'framework_frames': frameworkFrames,
    'timed_frames': timings.length,
    'frames_per_second': timings.length * 1000000 / elapsed.inMicroseconds,
    'build_p50_ms': _percentile((frame) => frame.buildDuration, .5),
    'build_p95_ms': _percentile((frame) => frame.buildDuration, .95),
    'raster_p50_ms': _percentile((frame) => frame.rasterDuration, .5),
    'raster_p95_ms': _percentile((frame) => frame.rasterDuration, .95),
  };

  @override
  String toString() {
    final data = toJson();
    String ms(String key) =>
        (data[key] as double?)?.toStringAsFixed(2) ?? 'n/a';
    return '$scenario: $updates updates, ${timings.length} timed frames '
        '($frameworkFrames framework frames) in ${elapsed.inMilliseconds} ms\n'
        '  build p50 ${ms('build_p50_ms')} ms, p95 ${ms('build_p95_ms')} ms\n'
        '  raster p50 ${ms('raster_p50_ms')} ms, p95 ${ms('raster_p95_ms')} ms';
  }
}
