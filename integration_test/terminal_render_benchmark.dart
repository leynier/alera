/// Frame-cost benchmark for the terminal surface.
///
/// Runs on a real device rather than in a widget test, because the number that
/// matters is what a frame costs end to end: a widget test records paint calls
/// and never plays them back, and a busy Alera spends its CPU in rasterization
/// and in the GTK embedder, not in building widgets.
///
/// Deliberately not named `*_test.dart`: `flutter test integration_test`
/// sweeps that pattern in CI, and this is a measurement tool, not a check.
/// Not a pass/fail test. It prints a report and asserts only that frames were
/// produced, so it can be run before and after a rendering change and compared.
///
///     flutter test integration_test/terminal_render_benchmark.dart -d linux
///
/// `BENCH_PUMP_MS` sets the real delay between frames (default 16, so ~60 fps).
/// Under Xvfb the numbers are software rasterization and are only comparable
/// with other Xvfb runs.
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xterm/xterm.dart' as xterm;

/// Wall time per scenario. Measuring by time rather than by frame count is what
/// makes the CPU figure comparable across cadences.
const _scenarioDuration = Duration(seconds: 8);

/// Agent output is dense and wide; sparse cells are the cheap case and would
/// flatter the painter.
const _lineWidth = 200;

/// Real delay between frames. The app currently drives one frame per vsync for
/// as long as output keeps arriving, so `BENCH_PUMP_MS=33` measures what
/// halving that cadence would save across the whole pipeline, embedder
/// included.
final _frameDelay = Duration(
  milliseconds: int.tryParse(Platform.environment['BENCH_PUMP_MS'] ?? '') ?? 16,
);

/// CPU seconds this process has burned, from `/proc/self/stat` (utime+stime).
///
/// Read from inside the test so a scenario can be charged its own cost, which
/// external sampling cannot do without guessing where one scenario ends.
double? _processCpuSeconds() {
  if (!Platform.isLinux) {
    return null;
  }
  try {
    final stat = File('/proc/self/stat').readAsStringSync();
    // The comm field can contain spaces and parentheses, so fields are counted
    // from after the closing parenthesis.
    final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
    final ticks = int.parse(fields[11]) + int.parse(fields[12]);
    // sysconf(_SC_CLK_TCK), 100 on every Linux Flutter supports.
    return ticks / 100;
  } catch (_) {
    return null;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<_Report> measure(
    WidgetTester tester,
    String scenario, {
    required void Function(int frame) onFrame,
    required xterm.Terminal terminal,
  }) async {
    // Warm-up first: the paragraph cache starts empty, and the first frames
    // would otherwise measure font layout rather than painting.
    for (var i = 0; i < 20; i++) {
      onFrame(i);
      await tester.pump();
      await Future<void>.delayed(_frameDelay);
    }

    final timings = <FrameTiming>[];
    void collect(List<FrameTiming> frames) => timings.addAll(frames);
    binding.addTimingsCallback(collect);

    final startedAt = DateTime.now();
    final cpuBefore = _processCpuSeconds();
    var frame = 0;
    while (DateTime.now().difference(startedAt) < _scenarioDuration) {
      onFrame(frame++);
      await tester.pump();
      await Future<void>.delayed(_frameDelay);
    }
    final elapsed = DateTime.now().difference(startedAt);
    final cpuAfter = _processCpuSeconds();

    // Timings arrive a frame late, so let the tail land before unsubscribing.
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    binding.removeTimingsCallback(collect);

    return _Report(
      scenario: scenario,
      viewWidth: terminal.viewWidth,
      viewHeight: terminal.viewHeight,
      frames: frame,
      elapsed: elapsed,
      cpuSeconds: cpuBefore == null || cpuAfter == null
          ? null
          : cpuAfter - cpuBefore,
      timings: timings,
    );
  }

  testWidgets('terminal frame cost while streaming output', (tester) async {
    final terminal = xterm.Terminal(maxLines: 4000);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF0B0D10),
          body: xterm.TerminalView(
            terminal,
            // Matches the shipped defaults closely enough that the cell count
            // per screen is representative.
            textStyle: const xterm.TerminalStyle(
              fontSize: 13,
              fontFamily: 'JetBrainsMono',
            ),
            padding: const EdgeInsets.all(8),
            cursorBlink: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final random = Random(7);
    final alphabet = List<String>.generate(
      _lineWidth,
      (i) => String.fromCharCode(33 + random.nextInt(90)),
    ).join();

    final reports = <_Report>[
      // Control: the same filled screen, nothing arriving, frames still pumped.
      // Whatever this costs is the price of producing a frame at all, which is
      // where the GTK embedder's per-frame work shows up.
      await measure(
        tester,
        'no output, frames still pumped',
        terminal: terminal,
        onFrame: (_) {},
      ),
      // One line per frame: a chatty agent.
      await measure(
        tester,
        'one line per frame',
        terminal: terminal,
        onFrame: (frame) => terminal.write('$frame $alphabet\r\n'),
      ),
      // A screenful per frame: a build log or a `cat` of a large file.
      await measure(
        tester,
        'one screenful per frame',
        terminal: terminal,
        onFrame: (frame) {
          for (var i = 0; i < terminal.viewHeight; i++) {
            terminal.write('$frame.$i $alphabet\r\n');
          }
        },
      ),
    ];

    // ignore: avoid_print
    print(
      '\n=== terminal render benchmark (frame delay '
      '${_frameDelay.inMilliseconds} ms) ===',
    );
    for (final report in reports) {
      // ignore: avoid_print
      print(report);
      expect(
        report.timings,
        isNotEmpty,
        reason: 'no frames were timed for ${report.scenario}',
      );
    }
  });
}

class _Report {
  _Report({
    required this.scenario,
    required this.viewWidth,
    required this.viewHeight,
    required this.frames,
    required this.elapsed,
    required this.cpuSeconds,
    required this.timings,
  });

  final String scenario;
  final int viewWidth;
  final int viewHeight;
  final int frames;
  final Duration elapsed;

  /// Process CPU for this scenario. Null off Linux.
  final double? cpuSeconds;
  final List<FrameTiming> timings;

  double _percentile(List<double> sorted, double fraction) {
    if (sorted.isEmpty) {
      return 0;
    }
    final index = ((sorted.length - 1) * fraction).round();
    return sorted[index];
  }

  List<double> _millis(Duration Function(FrameTiming) select) =>
      timings.map((timing) => select(timing).inMicroseconds / 1000).toList()
        ..sort();

  @override
  String toString() {
    final seconds = elapsed.inMicroseconds / 1000000;
    final build = _millis((timing) => timing.buildDuration);
    final raster = _millis((timing) => timing.rasterDuration);
    String row(String label, List<double> values) =>
        '$label median ${_percentile(values, 0.5).toStringAsFixed(2)} ms, '
        'p95 ${_percentile(values, 0.95).toStringAsFixed(2)} ms';
    final cpu = cpuSeconds == null
        ? 'cpu unavailable'
        : 'cpu ${(cpuSeconds! * 100 / seconds).toStringAsFixed(1)}% of a core';
    return '$scenario  [${viewWidth}x$viewHeight cells]\n'
        '  ${(frames / seconds).toStringAsFixed(1)} fps over '
        '${seconds.toStringAsFixed(1)} s, $cpu\n'
        '  ${row('build ', build)}\n'
        '  ${row('raster', raster)}';
  }
}
