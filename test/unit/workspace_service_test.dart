// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'fake_git_backend.dart';

part 'workspace_service_core_test_cases.dart';
part 'workspace_service_removal_test_cases.dart';
part 'workspace_service_test_harness.dart';

late Directory tempDir;
late _FakeWorkbenchRepository repository;
late FakeGitBackend gitBackend;
late WorkspaceService service;
late Project project;

void main() {
  group('WorkspaceService', () {
    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('alera-workspace-test-');
      repository = _FakeWorkbenchRepository();
      gitBackend = FakeGitBackend();
      service = WorkspaceService(
        repository: repository,
        projectService: ProjectService(gitBackend),
        gitBackend: gitBackend,
        workspaceRoot: WorkspaceRoot(
          override: p.join(tempDir.path, 'workspaces'),
        ),
        now: () => DateTime.utc(2026, 5, 20, 12),
      );
      project = Project(
        id: 'project-1',
        name: 'Alera',
        repoPath: p.join(tempDir.path, 'repo'),
        createdAt: DateTime.utc(2026, 5, 20),
        updatedAt: DateTime.utc(2026, 5, 20),
      );
      Directory(project.repoPath).createSync(recursive: true);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    _registerWorkspaceServiceCoreTests();
    _registerWorkspaceServiceRemovalTests();
  });
}
