import 'dart:async';

import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_host_enrollment.dart';
import 'package:alera/src/features/projects/presentation/project_host_enrollment_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 21);
  final project = Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/repo/alera',
    createdAt: now,
    updatedAt: now,
  );

  test('without an add function the runtime is unsupported', () async {
    final controller = ProjectHostEnrollmentController(null);
    addTearDown(controller.dispose);

    expect(controller.supported, isFalse);
    expect(await controller.add(project, 'ssh-mac'), isNull);
    expect(controller.adding, isFalse);
  });

  test(
    'add sends the trimmed path and remembers the refreshed project',
    () async {
      final calls = <(String, String?)>[];
      final controller = ProjectHostEnrollmentController((
        project,
        hostId,
        existingPath,
      ) async {
        calls.add((hostId, existingPath));
        return projectWithCheckout(
          project,
          ProjectCheckout(hostId: hostId, path: existingPath ?? '/cloned'),
        );
      });
      addTearDown(controller.dispose);
      controller.pathController.text = '  /srv/alera  ';

      final refreshed = await controller.add(project, 'ssh-mac');

      expect(calls, <(String, String?)>[('ssh-mac', '/srv/alera')]);
      expect(refreshed!.isOnHost('ssh-mac'), isTrue);
      expect(controller.resolve(project).isOnHost('ssh-mac'), isTrue);
      expect(controller.pathController.text, isEmpty);
      expect(controller.error, isNull);
    },
  );

  test('an empty path asks the host to clone', () async {
    String? sentPath = 'unset';
    final controller = ProjectHostEnrollmentController((
      project,
      hostId,
      existingPath,
    ) async {
      sentPath = existingPath;
      return project;
    });
    addTearDown(controller.dispose);

    await controller.add(project, 'ssh-mac');

    expect(sentPath, isNull);
  });

  test(
    'reports progress, ignores a second add, and keeps the failure',
    () async {
      final gate = Completer<Project>();
      var calls = 0;
      final controller = ProjectHostEnrollmentController((_, _, _) {
        calls++;
        return gate.future;
      });
      addTearDown(controller.dispose);
      final states = <bool>[];
      controller.addListener(() => states.add(controller.adding));

      final pending = controller.add(project, 'ssh-mac');
      expect(controller.adding, isTrue);
      expect(await controller.add(project, 'ssh-mac'), isNull);
      gate.completeError(StateError('The host refused the clone.'));

      expect(await pending, isNull);
      expect(calls, 1);
      expect(states, <bool>[true, false]);
      expect(controller.error, 'The host refused the clone.');
      expect(controller.resolve(project), same(project));

      controller.clearError();
      expect(controller.error, isNull);
    },
  );

  test('an add that finishes after dispose does not notify', () async {
    final gate = Completer<Project>();
    final controller = ProjectHostEnrollmentController(
      (_, _, _) => gate.future,
    );
    final pending = controller.add(project, 'ssh-mac');
    controller.dispose();
    gate.complete(project);

    expect(await pending, same(project));
  });
}
