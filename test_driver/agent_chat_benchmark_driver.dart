import 'dart:async';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

import 'agent_chat_benchmark_report.dart';

Future<void> main() async {
  final directory = Platform.environment['FLUTTER_TEST_OUTPUTS_DIR'];
  if (directory == null || directory.trim().isEmpty) {
    stderr.writeln(
      'Set FLUTTER_TEST_OUTPUTS_DIR to the private benchmark evidence directory.',
    );
    exit(2);
  }
  // integrationDriver's request timeout starts after an unbounded connect.
  // Bound the host process too, without enabling drive's screenshot handler.
  final watchdog = Timer(const Duration(minutes: 3), () {
    stderr.writeln(
      'Benchmark driver exceeded its three-minute connection/result deadline.',
    );
    exit(2);
  });
  try {
    await integrationDriver(
      timeout: const Duration(minutes: 2),
      writeResponseOnFailure: true,
      responseDataCallback: (data) async {
        await writeResponseData(
          data,
          destinationDirectory: directory,
          testOutputFilename: 'agent_chat_render_benchmark',
        );
        validateAgentChatBenchmarkReport(data);
      },
    );
  } finally {
    watchdog.cancel();
  }
}
