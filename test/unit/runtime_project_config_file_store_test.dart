import 'dart:async';

import 'package:alera/src/features/projects/application/project_config_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/infra/runtime_project_config_file_store.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RuntimeProjectConfigFileStore', () {
    final remoteOnly = Project(
      id: 'project-remote',
      name: 'Server Only',
      repoPath: '/home/dev/alera-projects/server-only',
      primaryHostId: 'ssh-box',
      createdAt: .utc(2026),
      updatedAt: .utc(2026),
    );

    test('asks the runtime for the effective config by project id', () async {
      final client = _FakeRuntimeHostClient()
        ..response = <String, Object?>{
          'origin': 'repoFile',
          'error': null,
          'config': <String, Object?>{
            'gitHostingProvider': 'gitlab',
            'newWorkspace': <String, Object?>{'sourceBranch': 'develop'},
          },
        };
      final store = RuntimeProjectConfigFileStore(client);

      final config = await store.load(remoteOnly);

      expect(client.types, <String>['projectConfig.effective']);
      expect(client.payloads.single, <String, Object?>{
        'projectId': 'project-remote',
      });
      expect(config?.gitHostingProvider, GitHostingProvider.gitlab);
      expect(config?.newWorkspace.sourceBranch, 'develop');
    });

    test('a project without a repo file is null', () async {
      final client = _FakeRuntimeHostClient()
        ..response = <String, Object?>{
          'origin': 'none',
          'config': <String, Object?>{},
        };

      expect(
        await RuntimeProjectConfigFileStore(client).load(remoteOnly),
        isNull,
      );
    });

    test('a UI override is not the repo file', () async {
      final client = _FakeRuntimeHostClient()
        ..response = <String, Object?>{
          'origin': 'uiOverride',
          'config': <String, Object?>{'gitHostingProvider': 'github'},
        };

      expect(
        await RuntimeProjectConfigFileStore(client).load(remoteOnly),
        isNull,
      );
    });

    test('a file the host could not parse throws its error', () async {
      final client = _FakeRuntimeHostClient()
        ..response = <String, Object?>{
          'origin': 'repoFile',
          'error': 'git_hosting_provider must be a string',
          'config': <String, Object?>{},
        };

      await expectLater(
        RuntimeProjectConfigFileStore(client).load(remoteOnly),
        throwsA(
          isA<ProjectConfigException>().having(
            (error) => error.message,
            'message',
            contains('git_hosting_provider'),
          ),
        ),
      );
    });
  });
}

final class _FakeRuntimeHostClient implements RuntimeHostClient {
  Object? response;
  final types = <String>[];
  final payloads = <Map<String, Object?>>[];
  final _events = StreamController<RuntimeHostEvent>.broadcast();

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    types.add(type);
    payloads.add(payload);
    return response;
  }
}
