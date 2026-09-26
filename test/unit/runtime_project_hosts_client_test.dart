import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/infra/runtime_project_hosts_client.dart';
import 'package:alera/src/features/projects/infra/runtime_project_management_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final calls = <(String, Map<String, Object?>, Duration?)>[];
  Object? response;
  RuntimeProjectHostsClient client() =>
      RuntimeProjectHostsClient((type, payload, timeout) async {
        calls.add((type, payload, timeout));
        return response;
      });

  setUp(calls.clear);

  test('list decodes the hosts and skips malformed rows', () async {
    response = <String, Object?>{
      'primaryHostId': 'local',
      'hosts': <Object?>[
        <String, Object?>{
          'hostId': 'local',
          'path': '/home/me/repo',
          'primary': true,
          'workspaceCount': 2,
        },
        <String, Object?>{'hostId': 'ssh-a', 'path': '/srv/repo'},
        <String, Object?>{'hostId': 'broken'},
      ],
    };

    final hosts = await client().list('project-1');

    expect(calls.single.$1, 'project.hosts.list');
    expect(calls.single.$2, <String, Object?>{'projectId': 'project-1'});
    expect(hosts, hasLength(2));
    expect(hosts.first.primary, isTrue);
    expect(hosts.first.workspaceCount, 2);
    expect(hosts.last.hostId, 'ssh-a');
    expect(hosts.last.primary, isFalse);
    expect(hosts.last.workspaceCount, 0);
  });

  test('add without a path lets the host clone, with a clone budget', () async {
    response = <String, Object?>{
      'hostId': 'ssh-a',
      'path': '/home/remote/alera-projects/alera',
    };

    final checkout = await client().add(
      projectId: 'project-1',
      hostId: 'ssh-a',
      path: '  ',
    );

    expect(calls.single.$1, 'project.hosts.add');
    expect(calls.single.$2, <String, Object?>{
      'projectId': 'project-1',
      'hostId': 'ssh-a',
    });
    expect(calls.single.$3, projectHostAddTimeout);
    expect(checkout.path, '/home/remote/alera-projects/alera');
  });

  test('add sends an existing path or an explicit clone source', () async {
    response = <String, Object?>{'hostId': 'ssh-a', 'path': '/srv/repo'};

    await client().add(
      projectId: 'project-1',
      hostId: 'ssh-a',
      path: ' /srv/repo ',
      cloneUrl: ' git@github.com:o/r.git ',
    );

    expect(calls.single.$2['path'], '/srv/repo');
    expect(calls.single.$2['cloneUrl'], 'git@github.com:o/r.git');
  });

  test('an older runtime is reported instead of decoded as empty', () async {
    response = <String, Object?>{};

    await expectLater(client().list('project-1'), throwsStateError);
    await expectLater(
      client().add(projectId: 'project-1', hostId: 'ssh-a'),
      throwsStateError,
    );
  });

  Map<String, Object?> storedProject({String kind = 'gitRepository'}) {
    return <String, Object?>{
      'id': 'project-9',
      'name': 'Api',
      'repoPath': '/srv/api',
      'createdAt': '2026-09-21T10:00:00.123456789Z',
      'updatedAt': '2026-09-21T10:00:00.123456789Z',
      'kind': kind,
    };
  }

  test('registerRemote registers an existing folder on a host', () async {
    response = <String, Object?>{
      'project': storedProject(kind: 'folder'),
      'checkout': <String, Object?>{'hostId': 'ssh-a', 'path': '/srv/api'},
    };

    final project = await client().registerRemote(
      hostId: 'ssh-a',
      path: ' /srv/api ',
      cloneUrl: ' ',
      name: ' Api ',
      kind: ProjectKind.folder,
    );

    expect(calls.single.$1, 'project.registerRemote');
    expect(calls.single.$2, <String, Object?>{
      'hostId': 'ssh-a',
      'path': '/srv/api',
      'name': 'Api',
      'kind': 'folder',
    });
    expect(calls.single.$3, projectHostAddTimeout);
    expect(project.id, 'project-9');
    expect(project.kind, ProjectKind.folder);
    // The stored project does not say where it lives; the checkout does.
    expect(project.isRemoteOnly, isTrue);
    expect(project.primaryHostId, 'ssh-a');
    expect(project.isOnHost('ssh-a'), isTrue);
    expect(project.isOnHost(null), isFalse);
  });

  test('registerRemote asks the host to clone when there is no path', () async {
    response = <String, Object?>{
      'project': <String, Object?>{
        ...storedProject(),
        'primaryHostId': 'ssh-a',
      },
    };

    final project = await client().registerRemote(
      hostId: 'ssh-a',
      cloneUrl: ' git@github.com:o/api.git ',
    );

    expect(calls.single.$2, <String, Object?>{
      'hostId': 'ssh-a',
      'cloneUrl': 'git@github.com:o/api.git',
    });
    expect(project.primaryHostId, 'ssh-a');
    expect(project.checkouts, isEmpty);
  });

  test('registerRemote reports a malformed answer as an old runtime', () async {
    for (final malformed in <Object?>[
      null,
      <String, Object?>{},
      <String, Object?>{'project': 'nope'},
      <String, Object?>{
        'project': <String, Object?>{'id': 'project-9'},
      },
    ]) {
      response = malformed;
      await expectLater(
        client().registerRemote(hostId: 'ssh-a', path: '/srv/api'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Update the runtime to add remote projects.',
          ),
        ),
      );
    }
  });

  test('a listed project keeps the hosts the runtime reports', () {
    final remoteOnly = projectFromRuntimeJson(<String, Object?>{
      ...storedProject(),
      'primaryHostId': 'ssh-a',
      'checkouts': <Object?>[
        <String, Object?>{'hostId': 'ssh-a', 'path': '/srv/api'},
        <String, Object?>{'hostId': 'broken'},
        'nope',
      ],
    });
    expect(remoteOnly.isRemoteOnly, isTrue);
    expect(remoteOnly.checkouts.single.path, '/srv/api');
    expect(remoteOnly.isOnHost('ssh-a'), isTrue);

    final legacy = projectFromRuntimeJson(<String, Object?>{
      ...storedProject(),
      'primaryHostId': ' ',
    });
    expect(legacy.isRemoteOnly, isFalse);
    expect(legacy.checkouts, isEmpty);
  });

  test('a project knows which hosts it is on', () {
    final now = DateTime.utc(2026, 9, 21);
    final project = Project.fromJson(<String, Object?>{
      'id': 'p',
      'name': 'Alera',
      'repoPath': '/home/me/alera',
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'primaryHostId': 'local',
      'checkouts': <Object?>[
        <String, Object?>{'hostId': 'local', 'path': '/home/me/alera'},
        <String, Object?>{'hostId': 'ssh-a', 'path': '/srv/alera'},
      ],
    });
    expect(project.isRemoteOnly, isFalse);
    expect(project.isOnHost(null), isTrue);
    expect(project.isOnHost(' '), isTrue);
    expect(project.isOnHost('ssh-a'), isTrue);
    expect(project.isOnHost('ssh-b'), isFalse);

    final legacy = Project.fromJson(<String, Object?>{
      'id': 'p',
      'name': 'Alera',
      'repoPath': '/home/me/alera',
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });
    expect(legacy.primaryHostId, 'local');
    expect(legacy.checkouts, isEmpty);
    expect(legacy.isOnHost(null), isTrue);
  });
}
