import 'package:alera_mobile/src/features/projects/domain/project_management_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips New Workspace prompt append', () {
    const config = MobileProjectConfig(
      promptAppend: 'Follow The Project Conventions.',
    );

    final restored = MobileProjectConfig.fromJson(config.toJson());

    expect(restored.promptAppend, 'Follow The Project Conventions.');
  });

  test('defaults New Workspace prompt append for older payloads', () {
    final config = MobileProjectConfig.fromJson(<String, Object?>{
      'worktree': <String, Object?>{},
    });

    expect(config.promptAppend, isEmpty);
  });
}
