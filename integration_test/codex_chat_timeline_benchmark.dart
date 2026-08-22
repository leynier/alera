/// Measures Codex chat timeline build and raster cost while a long thread is
/// receiving incremental app-server updates.
///
/// This is a non-gating comparison benchmark. It is deliberately not named
/// `*_test.dart`, so the integration test sweep does not run it in CI.
///
///     flutter test integration_test/codex_chat_timeline_benchmark.dart -d linux
library;

import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/codex_chat/application/codex_chat_controller.dart';
import 'package:alera/src/features/codex_chat/presentation/codex_chat_surface.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _turnCount = 240;
const _updateCount = 120;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Codex timeline incremental rendering benchmark', (tester) async {
    final client = _BenchmarkRuntimeClient();
    addTearDown(client.dispose);
    final container = ProviderContainer(
      overrides: [
        codexChatRuntimeClientProvider.overrideWithValue(client),
        settingsControllerProvider.overrideWith(_BenchmarkSettings.new),
      ],
    );
    addTearDown(container.dispose);
    final initial = Stopwatch()..start();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: aleraDarkTheme,
          darkTheme: aleraDarkTheme,
          themeMode: ThemeMode.dark,
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 800,
              child: CodexChatSurface(workspace: _workspace(), tab: _tab()),
            ),
          ),
        ),
      ),
    );
    for (
      var attempt = 0;
      attempt < 20 &&
          find.textContaining('Benchmark request').evaluate().isEmpty;
      attempt += 1
    ) {
      await tester.pump();
    }
    initial.stop();

    var visibleTurns = find
        .textContaining('Benchmark request')
        .evaluate()
        .length;
    expect(visibleTurns, greaterThan(0), reason: 'timeline never became ready');
    expect(visibleTurns, lessThan(_turnCount));

    final timeline = find.byKey(
      const ValueKey<String>('codex-timeline-scroll-view'),
    );
    await tester.fling(timeline, const Offset(0, -100000), 100000);
    await tester.pumpAndSettle();
    expect(find.text('Benchmark request ${_turnCount - 1}'), findsOneWidget);
    visibleTurns = find.textContaining('Benchmark request').evaluate().length;

    final timings = <FrameTiming>[];
    void collect(List<FrameTiming> values) => timings.addAll(values);
    binding.addTimingsCallback(collect);
    final updates = Stopwatch()..start();
    for (var index = 0; index < _updateCount; index += 1) {
      client.emitAssistantDelta(index);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    updates.stop();
    binding.removeTimingsCallback(collect);

    expect(
      container
          .read(codexChatControllerProvider('codex-benchmark-tab'))
          .snapshot
          .timelineCells
          .last
          .markdownText,
      'Streaming response revision ${_updateCount - 1}',
    );
    expect(
      find.textContaining('Streaming response revision ${_updateCount - 1}'),
      findsOneWidget,
    );
    expect(timings, isNotEmpty);
    final builds =
        timings
            .map((timing) => timing.buildDuration.inMicroseconds / 1000)
            .toList()
          ..sort();
    final rasters =
        timings
            .map((timing) => timing.rasterDuration.inMicroseconds / 1000)
            .toList()
          ..sort();
    // ignore: avoid_print
    print(
      'Codex timeline benchmark: turns=$_turnCount '
      'visible=$visibleTurns updates=$_updateCount '
      'initial=${initial.elapsedMilliseconds} ms '
      'updates=${updates.elapsedMilliseconds} ms '
      'build_p50=${_percentile(builds, 0.50).toStringAsFixed(2)} ms '
      'build_p95=${_percentile(builds, 0.95).toStringAsFixed(2)} ms '
      'raster_p50=${_percentile(rasters, 0.50).toStringAsFixed(2)} ms '
      'raster_p95=${_percentile(rasters, 0.95).toStringAsFixed(2)} ms',
    );
  });
}

double _percentile(List<double> sorted, double fraction) {
  final index = ((sorted.length - 1) * fraction).round();
  return sorted[index];
}

Workspace _workspace() {
  final now = DateTime.utc(2026);
  return Workspace(
    id: 'workspace-benchmark',
    projectId: 'project-benchmark',
    name: 'Benchmark',
    path: '/tmp/alera-codex-benchmark',
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
}

WorkspaceTabRecord _tab() {
  final now = DateTime.utc(2026);
  return WorkspaceTabRecord(
    id: 'codex-benchmark-tab',
    workspaceId: 'workspace-benchmark',
    kind: WorkspaceTabKind.codex,
    title: 'Codex Chat',
    createdAt: now,
    updatedAt: now,
  );
}

final class _BenchmarkSettings extends SettingsController {
  @override
  AleraSettings build() => AleraSettings.defaults;

  @override
  Future<void> updateCodexChat(CodexChatSettings settings) async {
    state = state.copyWith(codexChat: settings);
  }
}

final class _BenchmarkRuntimeClient implements RuntimeHostClient {
  final StreamController<RuntimeHostEvent> _events =
      StreamController<RuntimeHostEvent>.broadcast();

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    if (type == 'codex.thread.open') {
      return <String, Object?>{'snapshot': _initialSnapshot()};
    }
    if (type == 'codex.model.list') {
      return <String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'id': 'gpt-benchmark',
            'displayName': 'Benchmark Codex',
            'isDefault': true,
          },
        ],
      };
    }
    return <String, Object?>{'data': const <Object?>[]};
  }

  void emitAssistantDelta(int revision) {
    _events.add(
      RuntimeHostEvent('codexThreadChanged', <String, Object?>{
        'tabId': 'codex-benchmark-tab',
        'snapshotDelta': <String, Object?>{
          'timelineUpserts': <Object?>[
            <String, Object?>{
              'id': 'answer-${_turnCount - 1}',
              'turnId': 'turn-${_turnCount - 1}',
              'kind': 'assistantMessage',
              'status': 'inProgress',
              'isStreaming': true,
              'markdownText': 'Streaming response revision $revision',
            },
          ],
          'timelineRemovedIds': const <Object?>[],
          'eventsAppend': const <Object?>[],
        },
      }),
    );
  }

  Map<String, Object?> _initialSnapshot() => <String, Object?>{
    'timelineCells': <Object?>[
      for (var index = 0; index < _turnCount; index++) ...<Object?>[
        <String, Object?>{
          'id': 'user-$index',
          'turnId': 'turn-$index',
          'kind': 'userMessage',
          'status': 'completed',
          'markdownText': 'Benchmark request $index',
        },
        <String, Object?>{
          'id': 'answer-$index',
          'turnId': 'turn-$index',
          'kind': 'assistantMessage',
          'status': 'completed',
          'markdownText': 'Benchmark response $index',
        },
      ],
    ],
    'activeTurnId': 'turn-${_turnCount - 1}',
    'pendingRequests': const <Object?>[],
  };

  void dispose() => _events.close();
}
