import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_host_enrollment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 21);
  Project project({
    ProjectKind kind = ProjectKind.gitRepository,
    String primaryHostId = 'local',
    List<ProjectCheckout> checkouts = const <ProjectCheckout>[],
  }) {
    return Project(
      id: 'project-1',
      name: 'Alera',
      repoPath: '/repo/alera',
      createdAt: now,
      updatedAt: now,
      kind: kind,
      primaryHostId: primaryHostId,
      checkouts: checkouts,
    );
  }

  group('initialWorkspaceHostId', () {
    test('an ordinary project starts on this device', () {
      expect(
        initialWorkspaceHostId(project: project(), requested: null),
        isNull,
      );
      expect(initialWorkspaceHostId(project: null, requested: ' '), isNull);
    });

    test('a project that lives only on a server starts there', () {
      final remoteOnly = project(
        primaryHostId: 'ssh-mac',
        checkouts: const <ProjectCheckout>[
          ProjectCheckout(hostId: 'ssh-mac', path: '/Users/me/alera'),
        ],
      );
      expect(
        initialWorkspaceHostId(project: remoteOnly, requested: null),
        'ssh-mac',
      );
    });

    test('an explicit host wins', () {
      final remoteOnly = project(primaryHostId: 'ssh-mac');
      expect(
        initialWorkspaceHostId(project: remoteOnly, requested: 'ssh-win'),
        'ssh-win',
      );
    });
  });

  group('projectHostEnrollment', () {
    test('a host with a checkout is enrolled', () {
      final onMac = project(
        checkouts: const <ProjectCheckout>[
          ProjectCheckout(hostId: 'ssh-mac', path: '/Users/me/alera'),
        ],
      );
      expect(
        projectHostEnrollment(
          project: onMac,
          hostId: 'ssh-mac',
          supportsProjectHosts: true,
        ),
        ProjectHostEnrollment.enrolled,
      );
      expect(
        projectHostEnrollment(
          project: onMac,
          hostId: null,
          supportsProjectHosts: true,
        ),
        ProjectHostEnrollment.enrolled,
      );
    });

    test('a Git project can be added to a remote host it is not on', () {
      expect(
        projectHostEnrollment(
          project: project(),
          hostId: 'ssh-mac',
          supportsProjectHosts: true,
        ),
        ProjectHostEnrollment.addable,
      );
    });

    test('a folder project stays on its one host', () {
      expect(
        projectHostEnrollment(
          project: project(kind: ProjectKind.folder),
          hostId: 'ssh-mac',
          supportsProjectHosts: true,
        ),
        ProjectHostEnrollment.folderProject,
      );
    });

    test('this device cannot be added to a remote-only project', () {
      final remoteOnly = project(primaryHostId: 'ssh-mac');
      for (final hostId in <String?>[null, ' ', 'local']) {
        expect(
          projectHostEnrollment(
            project: remoteOnly,
            hostId: hostId,
            supportsProjectHosts: true,
          ),
          ProjectHostEnrollment.thisDevice,
        );
      }
    });

    test('an older runtime reports no checkouts, so every host is trusted', () {
      expect(
        projectHostEnrollment(
          project: project(),
          hostId: 'ssh-mac',
          supportsProjectHosts: false,
        ),
        ProjectHostEnrollment.enrolled,
      );
    });
  });

  group('projectHostRemovalBlockedReason', () {
    test('the only host cannot be removed', () {
      expect(
        projectHostRemovalBlockedReason(
          primary: true,
          workspaceCount: 0,
          hostCount: 1,
        ),
        "This is the project's only host.",
      );
    });

    test('the primary host cannot be removed', () {
      expect(
        projectHostRemovalBlockedReason(
          primary: true,
          workspaceCount: 0,
          hostCount: 2,
        ),
        "The primary host holds the project's main folder.",
      );
    });

    test('a host with workspaces cannot be removed', () {
      expect(
        projectHostRemovalBlockedReason(
          primary: false,
          workspaceCount: 2,
          hostCount: 2,
        ),
        'Remove the workspaces on this host first.',
      );
    });

    test('an idle secondary host can be removed', () {
      expect(
        projectHostRemovalBlockedReason(
          primary: false,
          workspaceCount: 0,
          hostCount: 2,
        ),
        isNull,
      );
    });
  });

  test('projectWithCheckout adds or replaces the checkout of one host', () {
    final added = projectWithCheckout(
      project(),
      const ProjectCheckout(hostId: 'ssh-mac', path: '/old'),
    );
    expect(added.isOnHost('ssh-mac'), isTrue);

    final replaced = projectWithCheckout(
      added,
      const ProjectCheckout(hostId: 'ssh-mac', path: '/new'),
    );
    expect(replaced.checkouts, hasLength(1));
    expect(replaced.checkouts.single.path, '/new');
  });
}
