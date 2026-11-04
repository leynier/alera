import 'package:flutter/foundation.dart';
import 'package:integration_test/integration_test.dart';

void captureAgentChatBenchmarkFailures(
  IntegrationTestWidgetsFlutterBinding binding,
) {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    // Profile-mode FlutterErrorDetails.toString omits the actual exception.
    // Keep bounded synthetic-test evidence while preserving the test handler.
    final exception = details.exceptionAsString();
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['agent_chat_benchmark_failure'] = <String, Object?>{
      'exception': exception.length > 2000
          ? exception.substring(0, 2000)
          : exception,
      'library': details.library,
    };
    previous?.call(details);
  };
}
