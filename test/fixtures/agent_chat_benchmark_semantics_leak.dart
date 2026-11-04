/// Expected-failure probe, invoked explicitly outside normal test discovery.
library;

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/agent_chat_benchmark_binding.dart';

void main() {
  final binding = AgentChatBenchmarkBinding();
  testWidgets('platform AX must not hide a leaked app semantics handle', (
    tester,
  ) async {
    tester.platformDispatcher.semanticsEnabledTestValue = true;
    addTearDown(tester.platformDispatcher.clearSemanticsEnabledTestValue);
    binding.ensureSemantics();
  }, timeout: const Timeout(Duration(seconds: 10)));
}
