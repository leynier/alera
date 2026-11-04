const _scenarios = <String>{
  'stream',
  'history-and-stream',
  'history-live-idle',
  'history-completed-idle',
};

void validateAgentChatBenchmarkReport(Map<String, dynamic>? data) {
  final benchmark = data?['agent_chat_render_benchmark'];
  if (benchmark is! Map || benchmark['reports'] is! List) {
    throw StateError('The benchmark did not return its measurement report.');
  }
  final reports = benchmark['reports'] as List;
  final names = <String>{};
  for (final report in reports) {
    if (report is! Map || report['scenario'] is! String) {
      throw StateError('The benchmark returned an invalid scenario report.');
    }
    final name = report['scenario'] as String;
    if (!names.add(name) || !_scenarios.contains(name)) {
      throw StateError('The benchmark returned an unexpected scenario.');
    }
    if (name == 'stream' || name == 'history-and-stream') {
      final updates = report['updates'];
      final frames = report['timed_frames'];
      if (updates is! num || updates <= 0 || frames is! num || frames <= 0) {
        throw StateError('Streaming produced no measured native frames.');
      }
    }
  }
  if (names.length != _scenarios.length) {
    throw StateError('The benchmark did not measure all four scenarios.');
  }
}
