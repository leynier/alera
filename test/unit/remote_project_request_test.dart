import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/remote_project_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RemoteProjectRequest? build({
    String? hostId = 'ssh-a',
    RemoteProjectSource source = RemoteProjectSource.existingFolder,
    String path = '',
    String cloneUrl = '',
    String name = '',
    ProjectKind kind = ProjectKind.gitRepository,
  }) {
    return remoteProjectRequestFrom(
      hostId: hostId,
      source: source,
      path: path,
      cloneUrl: cloneUrl,
      name: name,
      kind: kind,
    );
  }

  test('a host is required, and this device is not one', () {
    expect(build(hostId: null, path: '/srv/api'), isNull);
    expect(build(hostId: '  ', path: '/srv/api'), isNull);
    expect(build(hostId: 'local', path: '/srv/api'), isNull);
  });

  test('an existing folder needs a path and keeps the chosen kind', () {
    expect(build(path: '   '), isNull);
    // The URL of the other source never stands in for the folder.
    expect(build(cloneUrl: 'git@github.com:o/api.git'), isNull);

    final request = build(
      hostId: ' ssh-a ',
      path: r'  C:\work\api ',
      cloneUrl: 'git@github.com:o/api.git',
      name: '  Api ',
      kind: ProjectKind.folder,
    )!;
    expect(request.hostId, 'ssh-a');
    expect(request.path, r'C:\work\api');
    expect(request.cloneUrl, isNull);
    expect(request.name, 'Api');
    expect(request.kind, ProjectKind.folder);
  });

  test('a clone needs a URL and is always a Git project', () {
    expect(build(source: RemoteProjectSource.cloneRepository), isNull);
    expect(
      build(source: RemoteProjectSource.cloneRepository, path: '/srv/api'),
      isNull,
    );

    final request = build(
      source: RemoteProjectSource.cloneRepository,
      path: '/srv/api',
      cloneUrl: ' https://github.com/o/api.git ',
      kind: ProjectKind.folder,
    )!;
    expect(request.cloneUrl, 'https://github.com/o/api.git');
    expect(request.path, isNull);
    expect(request.name, isNull);
    expect(request.kind, ProjectKind.gitRepository);
  });
}
