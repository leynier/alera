import 'dart:async';
import 'dart:convert';

import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/infra/runtime_workspace_files_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'lists remote workspace children through workspace.files.list',
    () async {
      final client = _FakeRuntimeHostClient()
        ..responses['status.get'] = <String, Object?>{
          'runtimeCapabilities': <String>[
            aleraRuntimeHostRemoteSshWorkspacesCapability,
          ],
        }
        ..responses['workspace.files.list'] = <String, Object?>{
          'entries': <Object?>[
            <String, Object?>{
              'relativePath': 'lib',
              'name': 'lib',
              'kind': 'directory',
              'size': 0,
              'isHidden': false,
              'hasChildrenHint': true,
            },
            <String, Object?>{
              'relativePath': 'readme.md',
              'name': 'readme.md',
              'kind': 'file',
              'size': 12,
              'isHidden': false,
              'hasChildrenHint': false,
            },
          ],
        };
      final files = RuntimeWorkspaceFilesClient(client);

      final entries = await files.listChildren(
        workspaceId: 'workspace-1',
        relativePath: '',
        hideIgnored: true,
      );

      expect(entries, hasLength(2));
      expect(entries.first.kind, native.WorkspaceFileKind.directory);
      expect(entries.last.name, 'readme.md');
      expect(client.payloads['workspace.files.list']!.single, <String, Object?>{
        'workspaceId': 'workspace-1',
        'relativePath': '',
        'hideIgnored': true,
      });
    },
  );

  test('reads a remote text file through workspace.files.read', () async {
    final client = _FakeRuntimeHostClient()
      ..responses['status.get'] = <String, Object?>{
        'runtimeCapabilities': <String>[
          aleraRuntimeHostRemoteSshWorkspacesCapability,
        ],
      }
      ..responses['workspace.files.read'] = <String, Object?>{
        'relativePath': 'readme.md',
        'offset': 0,
        'nextOffset': 5,
        'totalBytes': 5,
        'mimeType': 'text/markdown',
        'isText': true,
        'dataBase64': base64Encode(utf8.encode('hello')),
      };
    final files = RuntimeWorkspaceFilesClient(client);

    final file = await files.readEditorTextFile(
      workspaceId: 'workspace-1',
      relativePath: 'readme.md',
    );

    expect(file.displayContent, 'hello');
    expect(file.rawContent, 'hello');
  });

  test('WorkspaceFileService routes remote list and read', () async {
    final remote = _RecordingRemoteFiles();
    final service = WorkspaceFileService(remoteFiles: remote);
    final workspace = _workspace(hostId: 'ssh-box');

    await service.listWorkspaceChildren(
      workspace: workspace,
      relativePath: '',
      hideIgnored: true,
    );
    await service.readWorkspaceEditorTextFile(
      workspace: workspace,
      relativePath: 'readme.md',
      tabSize: 4,
    );

    expect(remote.listedWorkspaceId, 'workspace-1');
    expect(remote.readWorkspaceId, 'workspace-1');
  });

  test('WorkspaceFileService refuses remote writes', () async {
    final service = WorkspaceFileService(remoteFiles: _RecordingRemoteFiles());

    await expectLater(
      service.writeWorkspaceEditorTextFile(
        workspace: _workspace(hostId: 'ssh-box'),
        relativePath: 'readme.md',
        currentDisplayContent: 'x',
        originalRawContent: 'x',
        originalDisplayContent: 'x',
        expectedContentToken: 'token',
        overwriteIfChanged: false,
        tabSize: 4,
      ),
      throwsA(isA<WorkspaceException>()),
    );
  });
}

Workspace _workspace({required String hostId}) {
  final now = DateTime.utc(2026, 9, 8);
  return Workspace(
    id: 'workspace-1',
    projectId: 'project-1',
    name: 'Feature',
    path: '/remote/feature',
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.linked,
    status: WorkspaceStatus.active,
    hostId: hostId,
  );
}

class _RecordingRemoteFiles implements RuntimeWorkspaceFiles {
  String? listedWorkspaceId;
  String? readWorkspaceId;

  @override
  Future<List<native.WorkspaceFileEntry>> listChildren({
    required String workspaceId,
    required String relativePath,
    required bool hideIgnored,
  }) async {
    listedWorkspaceId = workspaceId;
    return const <native.WorkspaceFileEntry>[];
  }

  @override
  Future<native.WorkspaceEditorTextFile> readEditorTextFile({
    required String workspaceId,
    required String relativePath,
  }) async {
    readWorkspaceId = workspaceId;
    return native.WorkspaceEditorTextFile(
      rawContent: '',
      displayContent: '',
      contentToken: 'token',
      modifiedMillis: 0,
      size: BigInt.zero,
    );
  }

  @override
  Future<native.WorkspaceTextFile> readTextFile({
    required String workspaceId,
    required String relativePath,
  }) async {
    readWorkspaceId = workspaceId;
    return native.WorkspaceTextFile(
      content: '',
      contentToken: 'token',
      modifiedMillis: 0,
      size: BigInt.zero,
    );
  }
}

final class _FakeRuntimeHostClient implements RuntimeHostClient {
  final responses = <String, Object?>{};
  final payloads = <String, List<Map<String, Object?>>>{};
  final _events = StreamController<RuntimeHostEvent>.broadcast();

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    payloads.putIfAbsent(type, () => <Map<String, Object?>>[]).add(payload);
    return responses[type];
  }
}
