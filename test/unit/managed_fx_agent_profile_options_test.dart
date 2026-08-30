import 'package:alera/src/features/agent_profiles/domain/managed_agent_profile_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('renders managed fx options', () {
    expect(
      managedAgentCommandPreview(.fx, const <String, Object?>{
        'resumeLast': true,
        'noAdditionalDirs': true,
        'record': true,
      }),
      'fx --continue --no-additional-dirs --record',
    );
    expect(managedAgentCommandPreview(.fx, const {}), 'fx');
  });
}
