import 'package:alera/src/features/projects/domain/project_config.dart';
import 'package:alera/src/features/pull_requests/domain/git_hosting_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProjectConfig.gitHostingProvider serialization', () {
    test('round-trips through JSON', () {
      const config = ProjectConfig(
        gitHostingProvider: GitHostingProvider.azureDevops,
      );
      final json = config.toMap();
      final restored = ProjectConfig.fromJson(json);
      expect(restored.gitHostingProvider, GitHostingProvider.azureDevops);
      expect(restored, config);
    });

    test('defaults to null (auto-detect) when omitted', () {
      final config = ProjectConfig.fromJson(<String, Object?>{});
      expect(config.gitHostingProvider, isNull);
      expect(config.isEmpty, isTrue);
    });

    test('old rows without the field still deserialize', () {
      // Legacy blob shape: only the worktree table was persisted.
      final legacy = <String, Object?>{
        'worktree': <String, Object?>{
          'copy': <Object?>[],
          'setup': <Object?>[],
        },
      };
      final config = ProjectConfig.fromJson(legacy);
      expect(config.gitHostingProvider, isNull);
    });

    test('a provider override makes the config non-empty', () {
      const config = ProjectConfig(
        gitHostingProvider: GitHostingProvider.github,
      );
      expect(config.isEmpty, isFalse);
    });
  });
}
