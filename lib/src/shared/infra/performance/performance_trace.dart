import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

const bool kAleraPerformanceTraceEnabled = .fromEnvironment('ALERA_PERF_TRACE');

abstract final class AleraPerformanceTrace {
  static final Stopwatch _startupStopwatch = Stopwatch();
  static bool _firstFrameScheduled = false;

  static void startStartup() {
    if (!kAleraPerformanceTraceEnabled) {
      return;
    }
    _startupStopwatch
      ..reset()
      ..start();
    mark('startup_started');
  }

  static void mark(String name, {Map<String, Object?> arguments = const {}}) {
    if (!kAleraPerformanceTraceEnabled) {
      return;
    }
    final payload = <String, Object?>{
      'name': name,
      'elapsedMicros': _startupStopwatch.elapsedMicroseconds,
      if (arguments.isNotEmpty) 'arguments': arguments,
    };
    developer.Timeline.instantSync('alera.$name', arguments: arguments);
    final message = 'ALERA_PERF ${jsonEncode(payload)}';
    developer.log(message, name: 'alera.performance');
    debugPrintSynchronously(message);
  }

  static void recordFirstFrame() {
    if (!kAleraPerformanceTraceEnabled || _firstFrameScheduled) {
      return;
    }
    _firstFrameScheduled = true;
    SchedulerBinding.instance.addTimingsCallback(_handleFrameTimings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      mark('first_frame_presented');
    });
  }

  static T measureSync<T>(
    String name,
    T Function() operation, {
    Map<String, Object?> arguments = const {},
  }) {
    if (!kAleraPerformanceTraceEnabled) {
      return operation();
    }
    developer.Timeline.startSync('alera.$name', arguments: arguments);
    final stopwatch = Stopwatch()..start();
    try {
      return operation();
    } finally {
      stopwatch.stop();
      developer.Timeline.finishSync();
      mark(
        name,
        arguments: <String, Object?>{
          ...arguments,
          'durationMicros': stopwatch.elapsedMicroseconds,
        },
      );
    }
  }

  static Future<T> measureAsync<T>(
    String name,
    Future<T> Function() operation, {
    Map<String, Object?> arguments = const {},
  }) async {
    if (!kAleraPerformanceTraceEnabled) {
      return operation();
    }
    final task = developer.TimelineTask()..start('alera.$name');
    final stopwatch = Stopwatch()..start();
    try {
      return await operation();
    } finally {
      stopwatch.stop();
      task.finish(arguments: arguments);
      mark(
        name,
        arguments: <String, Object?>{
          ...arguments,
          'durationMicros': stopwatch.elapsedMicroseconds,
        },
      );
    }
  }

  static void _handleFrameTimings(List<FrameTiming> timings) {
    if (timings.isEmpty) {
      return;
    }
    SchedulerBinding.instance.removeTimingsCallback(_handleFrameTimings);
    final timing = timings.first;
    mark(
      'first_frame_timing',
      arguments: <String, Object?>{
        'buildMicros': timing.buildDuration.inMicroseconds,
        'rasterMicros': timing.rasterDuration.inMicroseconds,
        'totalMicros': timing.totalSpan.inMicroseconds,
      },
    );
  }
}
