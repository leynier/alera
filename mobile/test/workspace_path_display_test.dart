import 'package:alera_mobile/src/features/workbench/presentation/pull_request_checks_section.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_path_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('workspaceFileParentLabel', () {
    test('returns the file name for a root file', () {
      expect(workspaceFileBaseName('main.dart'), 'main.dart');
      expect(workspaceFileDirectory('main.dart'), isNull);
      expect(workspaceFileParentLabel('main.dart'), isNull);
    });

    test('keeps a short directory intact', () {
      expect(workspaceFileBaseName('lib/main.dart'), 'main.dart');
      expect(workspaceFileDirectory('lib/main.dart'), 'lib');
      expect(workspaceFileParentLabel('lib/main.dart'), 'lib');
    });

    test('keeps the last two directory segments of a long path', () {
      expect(
        workspaceFileBaseName(
          'lib/src/features/pull_requests/domain/review_stack_workspace_models.dart',
        ),
        'review_stack_workspace_models.dart',
      );
      expect(
        workspaceFileParentLabel(
          'lib/src/features/pull_requests/domain/review_stack_workspace_models.dart',
        ),
        'pull_requests/domain',
      );
    });

    test('normalizes windows separators', () {
      expect(
        workspaceFileParentLabel(
          r'lib\src\features\workbench\application\foo.dart',
        ),
        'workbench/application',
      );
    });
  });

  group('displayPullRequestCheckName', () {
    test('collapses github matrix expressions', () {
      expect(
        displayPullRequestCheckName(r'build app ${{ matrix.platform }}'),
        'build app {platform}',
      );
      expect(
        displayPullRequestCheckName(
          r'build runtime ${{ matrix.platform }} ${{ matrix.arch }}',
        ),
        'build runtime {platform} {arch}',
      );
    });

    test('leaves ordinary check names unchanged', () {
      expect(displayPullRequestCheckName('cleanup'), 'cleanup');
    });
  });
}
