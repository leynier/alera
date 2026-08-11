import 'package:alera/src/features/agent_usage/application/agent_usage_period_memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults to seven days and remembers the last in-memory period', () {
    final memory = AgentUsagePeriodMemory();

    expect(memory.days, 7);
    memory.select(30);
    expect(memory.days, 30);
    memory.select(90);
    expect(memory.days, 90);
  });

  test('rejects periods that the Usage selector does not support', () {
    final memory = AgentUsagePeriodMemory();

    expect(() => memory.select(14), throwsArgumentError);
  });
}
