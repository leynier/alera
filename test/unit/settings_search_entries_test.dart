import 'package:alera/src/features/settings/presentation/settings_search_entries.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('orchestration skill is searchable in the agents skill group', () {
    final entry = agentsSearchEntries.singleWhere(
      (candidate) => candidate.title == 'Alera Orchestration Skill',
    );

    expect(entry.matches('orchestration'), isTrue);
    expect(entry.groupId, 'cliSkill');
  });
}
