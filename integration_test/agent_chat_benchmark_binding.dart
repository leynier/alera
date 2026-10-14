import 'package:integration_test/integration_test.dart';

/// Keeps Flutter 3.47.2's live test harness without its idle frame loop.
final class AgentChatBenchmarkBinding
    extends IntegrationTestWidgetsFlutterBinding {
  AgentChatBenchmarkBinding() {
    framePolicy = .benchmark;
  }

  @override
  void scheduleFrame() {
    // The pinned SDK's benchmark policy suppresses even widget requests.
    // Scheduling is synchronous, so drawing still observes benchmark policy.
    framePolicy = .fullyLive;
    try {
      super.scheduleFrame();
    } finally {
      framePolicy = .benchmark;
    }
  }

  @override
  void scheduleForcedFrame() {
    framePolicy = .fullyLive;
    try {
      super.scheduleForcedFrame();
    } finally {
      framePolicy = .benchmark;
    }
  }

  @override
  int get debugOutstandingSemanticsHandles =>
      // SemanticsBinding owns exactly one handle while platform AX is enabled.
      // Keep every app/test handle visible to WidgetTester's leak invariant.
      super.debugOutstandingSemanticsHandles -
      (platformDispatcher.semanticsEnabled ? 1 : 0);
}
