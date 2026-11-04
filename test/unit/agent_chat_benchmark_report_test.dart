import 'package:flutter_test/flutter_test.dart';

import '../../test_driver/agent_chat_benchmark_report.dart';

void main() {
  Map<String, dynamic> report() => <String, dynamic>{
    'agent_chat_render_benchmark': <String, dynamic>{
      'reports': <Map<String, dynamic>>[
        for (final scenario in <String>[
          'stream',
          'history-and-stream',
          'history-live-idle',
          'history-completed-idle',
        ])
          <String, dynamic>{
            'scenario': scenario,
            'updates': scenario.contains('idle') ? 0 : 10,
            'timed_frames': scenario.contains('idle') ? 0 : 10,
          },
      ],
    },
  };

  test('rejects a successful empty suite instead of accepting null data', () {
    expect(() => validateAgentChatBenchmarkReport(null), throwsStateError);
    expect(() => validateAgentChatBenchmarkReport({}), throwsStateError);
  });

  test('accepts measured streams with naturally frame-free completed idle', () {
    validateAgentChatBenchmarkReport(report());
  });

  test('rejects missing and duplicate scenarios', () {
    final data = report();
    final rows = data['agent_chat_render_benchmark']['reports'] as List;
    rows.removeLast();
    expect(() => validateAgentChatBenchmarkReport(data), throwsStateError);
    rows.add(rows.first);
    expect(() => validateAgentChatBenchmarkReport(data), throwsStateError);
  });

  test('rejects unmeasured native streaming', () {
    final data = report();
    data['agent_chat_render_benchmark']['reports'][0]['timed_frames'] = 0;
    expect(() => validateAgentChatBenchmarkReport(data), throwsStateError);
  });
}
