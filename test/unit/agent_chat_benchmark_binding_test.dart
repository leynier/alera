import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/agent_chat_benchmark_binding.dart';

void main() {
  final binding = AgentChatBenchmarkBinding();
  var frames = 0;
  binding.addPersistentFrameCallback((_) => frames += 1);

  testWidgets('platform AX transitions preserve app semantics handles', (
    tester,
  ) async {
    tester.platformDispatcher.semanticsEnabledTestValue = false;
    addTearDown(tester.platformDispatcher.clearSemanticsEnabledTestValue);
    final baseline = binding.debugOutstandingSemanticsHandles;
    expect(baseline, 1, reason: 'WidgetTester owns its normal test handle');

    tester.platformDispatcher.semanticsEnabledTestValue = true;
    expect(binding.semanticsEnabled, isTrue);
    expect(binding.debugOutstandingSemanticsHandles, baseline);
    final appHandle = binding.ensureSemantics();
    try {
      expect(binding.debugOutstandingSemanticsHandles, baseline + 1);
      tester.platformDispatcher.semanticsEnabledTestValue = false;
      expect(binding.debugOutstandingSemanticsHandles, baseline + 1);
      tester.platformDispatcher.semanticsEnabledTestValue = true;
      expect(binding.debugOutstandingSemanticsHandles, baseline + 1);
    } finally {
      appHandle.dispose();
    }
    expect(binding.debugOutstandingSemanticsHandles, baseline);
    // AX remains enabled until after WidgetTester's end-of-test verification.
  });

  testWidgets('animation requests continue until the ticker stops', (
    tester,
  ) async {
    var ticks = 0;
    final finished = Completer<void>();
    late final Ticker ticker;
    ticker = Ticker((_) {
      ticks += 1;
      if (ticks == 3) {
        ticker.stop();
        // A ticker runs before drawing; observe idle after its final draw.
        binding.addPostFrameCallback((_) => finished.complete());
      }
    });
    addTearDown(ticker.dispose);
    ticker.start();
    await tester.runAsync(
      () => finished.future.timeout(const Duration(seconds: 2)),
    );
    expect(ticks, 3);
    final completedFrames = frames;
    await tester.runAsync(
      () => Future.pause(const Duration(milliseconds: 100)),
    );
    expect(frames, completedFrames);
    expect(binding.hasScheduledFrame, isFalse);
  }, timeout: const Timeout(Duration(seconds: 10)));

  testWidgets('widget requests draw naturally and idle stops drawing', (
    tester,
  ) async {
    final value = ValueNotifier<int>(0);
    addTearDown(value.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: .ltr,
        child: ValueListenableBuilder<int>(
          valueListenable: value,
          builder: (_, count, _) => Text('$count'),
        ),
      ),
    );
    expect(find.text('0'), findsOneWidget);
    expect(
      binding.framePolicy,
      LiveTestWidgetsFlutterBindingFramePolicy.benchmark,
    );

    await tester.runAsync(
      () => Future.pause(const Duration(milliseconds: 100)),
    );
    final idleFrames = frames;
    await tester.runAsync(
      () => Future.pause(const Duration(milliseconds: 100)),
    );
    expect(
      frames,
      idleFrames,
      reason: 'the live harness must not keep drawing',
    );
    expect(binding.hasScheduledFrame, isFalse);

    final nextFrame = Completer<void>();
    binding.addPostFrameCallback((_) => nextFrame.complete());
    value.value = 1;
    expect(binding.hasScheduledFrame, isTrue);
    expect(
      binding.framePolicy,
      LiveTestWidgetsFlutterBindingFramePolicy.benchmark,
    );
    await tester.runAsync(
      () => nextFrame.future.timeout(const Duration(seconds: 2)),
    );
    expect(find.text('1'), findsOneWidget);
    expect(frames, greaterThan(idleFrames));

    final completedFrames = frames;
    await tester.runAsync(
      () => Future.pause(const Duration(milliseconds: 100)),
    );
    expect(frames, completedFrames);
    expect(binding.hasScheduledFrame, isFalse);

    final forcedFrame = Completer<void>();
    binding.addPostFrameCallback((_) => forcedFrame.complete());
    binding.scheduleForcedFrame();
    expect(binding.hasScheduledFrame, isTrue);
    expect(
      binding.framePolicy,
      LiveTestWidgetsFlutterBindingFramePolicy.benchmark,
    );
    await tester.runAsync(
      () => forcedFrame.future.timeout(const Duration(seconds: 2)),
    );
    final afterForcedFrame = frames;
    await tester.runAsync(
      () => Future.pause(const Duration(milliseconds: 100)),
    );
    expect(frames, afterForcedFrame);
    expect(binding.hasScheduledFrame, isFalse);
    // Normal testWidgets unmounting and teardown still execute after this test.
  }, timeout: const Timeout(Duration(seconds: 10)));
}
