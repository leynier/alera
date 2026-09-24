import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('voice home ids stay out of ordinary workspace identity', () {
    expect(isVoiceHomeProjectId('alera-home'), isTrue);
    expect(isVoiceHomeWorkspaceId('alera-home'), isTrue);
    expect(isVoiceHomeProjectId('payments'), isFalse);
    expect(isVoiceHomeWorkspaceId('workspace-1'), isFalse);
  });
}
