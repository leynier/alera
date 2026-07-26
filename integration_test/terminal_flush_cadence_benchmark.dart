/// What a streaming terminal costs through the app's own scheduling.
///
/// The sibling `terminal_render_benchmark.dart` drives xterm directly and
/// pumps its own frames, which measures what a frame costs. This one lets the
/// runtime decide when frames happen: output is fed at a fixed real rate and
/// `XtermTerminalSessionHandle` schedules the flushes, so the number it reports
/// is the one that changes when the flush cadence changes.
///
///     flutter test integration_test/terminal_flush_cadence_benchmark.dart -d linux
///
/// Deliberately not named `*_test.dart`: `flutter test integration_test`
/// sweeps that pattern in CI, and this is a measurement tool, not a check.
/// Not a pass/fail test. Run it, stash the flush-cadence change, run it again,
/// and compare.
library;

import 'dart:io';
import 'dart:math';

import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// How long output keeps arriving.
const _duration = Duration(seconds: 8);

/// Gap between writes from the fake producer. Faster than any display can show,
/// which is the case the cadence floor exists for: an agent or a build log does
/// not wait for vsync.
const _writeInterval = Duration(milliseconds: 8);

const _lineWidth = 200;

double? _processCpuSeconds() {
  if (!Platform.isLinux) {
    return null;
  }
  try {
    final stat = File('/proc/self/stat').readAsStringSync();
    final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
    return (int.parse(fields[11]) + int.parse(fields[12])) / 100;
  } catch (_) {
    return null;
  }
}

Workspace _workspace() {
  final now = DateTime.utc(2026, 7, 26);
  return Workspace(
    id: 'workspace-bench',
    projectId: 'project-bench',
    name: 'Bench',
    branch: 'main',
    path: '/repo/bench',
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
}

WorkspaceTabRecord _tab() {
  final now = DateTime.utc(2026, 7, 26);
  return WorkspaceTabRecord(
    id: 'tab-bench',
    workspaceId: 'workspace-bench',
    title: 'Bench',
    createdAt: now,
    updatedAt: now,
    payload: const <String, Object?>{},
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cost of a terminal streaming through the runtime', (
    tester,
  ) async {
    // Frames must be driven by the runtime's own `scheduleFrameCallback`, not
    // by the test pumping them, or the cadence under test is the test's.
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

    final runtime = XtermTerminalRuntime();
    addTearDown(runtime.dispose);
    final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF0B0D10),
          body: session.buildView(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final visibility = acquireTerminalVisibilityForTesting(session);
    addTearDown(visibility.dispose);

    final random = Random(7);
    final line = List<String>.generate(
      _lineWidth,
      (i) => String.fromCharCode(33 + random.nextInt(90)),
    ).join();

    final timings = <FrameTiming>[];
    void collect(List<FrameTiming> frames) => timings.addAll(frames);

    // Warm the paragraph cache so the measurement is not font layout.
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        queueTerminalOutputForTesting(session, '$i $line\r\n');
        await Future<void>.delayed(_writeInterval);
      }
    });

    final warmUpFlushes = terminalOutputFlushCountForTesting(session);
    binding.addTimingsCallback(collect);
    final startedAt = DateTime.now();
    final cpuBefore = _processCpuSeconds();
    var writes = 0;
    await tester.runAsync(() async {
      while (DateTime.now().difference(startedAt) < _duration) {
        queueTerminalOutputForTesting(session, '${writes++} $line\r\n');
        await Future<void>.delayed(_writeInterval);
      }
    });
    final elapsed = DateTime.now().difference(startedAt);
    final cpu = cpuBefore == null ? null : _processCpuSeconds()! - cpuBefore;
    binding.removeTimingsCallback(collect);

    final flushes = terminalOutputFlushCountForTesting(session) - warmUpFlushes;
    final seconds = elapsed.inMicroseconds / 1000000;
    final rasters =
        timings.map((t) => t.rasterDuration.inMicroseconds / 1000).toList()
          ..sort();
    final median = rasters.isEmpty ? 0.0 : rasters[rasters.length ~/ 2];
    // ignore: avoid_print
    print(
      '\n=== terminal flush cadence ===\n'
      '  ${(writes / seconds).toStringAsFixed(0)} writes/s in, '
      '${(flushes / seconds).toStringAsFixed(1)} flushes/s out '
      '(${(timings.length / seconds).toStringAsFixed(1)} binding frames/s)\n'
      '  cpu ${cpu == null ? '?' : (cpu * 100 / seconds).toStringAsFixed(1)}% '
      'of a core over ${seconds.toStringAsFixed(1)} s\n'
      '  raster median ${median.toStringAsFixed(2)} ms',
    );

    expect(timings, isNotEmpty, reason: 'no frames were produced');
  });
}
