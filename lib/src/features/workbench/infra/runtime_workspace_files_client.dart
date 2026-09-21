import 'dart:convert';

import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;

part 'runtime_workspace_files_wire_decoders.dart';

const int remoteWorkspaceFileReadChunkBytes = 256 * 1024;
const int remoteWorkspaceFileReadMaxBytes = 2 * 1024 * 1024;

/// The wire code the runtime uses for a typed workspace file error; its
/// `kind` detail names a `WorkspaceFileErrorKind` so the desktop can rethrow
/// the same exception the native bridge throws for a local checkout.
const String runtimeWorkspaceFileErrorCode = 'workspaceFile';

abstract interface class RuntimeWorkspaceFiles {
  Future<List<native.WorkspaceFileEntry>> listChildren({
    required String workspaceId,
    required String relativePath,
    required bool hideIgnored,
  });

  Future<native.WorkspaceEditorTextFile> readEditorTextFile({
    required String workspaceId,
    required String relativePath,
    required int tabSize,
  });

  Future<native.WorkspaceTextFile> readTextFile({
    required String workspaceId,
    required String relativePath,
  });

  Future<native.WorkspaceEditorTextFile> writeEditorTextFile({
    required String workspaceId,
    required String relativePath,
    required String currentDisplayContent,
    required String? originalRawContent,
    required String? originalDisplayContent,
    required String? expectedContentToken,
    required bool overwriteIfChanged,
    required int tabSize,
  });

  Future<native.WorkspaceTextFile> writeTextFile({
    required String workspaceId,
    required String relativePath,
    required String content,
    required String? expectedContentToken,
    required bool overwriteIfChanged,
  });

  Future<native.WorkspaceFileEntry> createEntry({
    required String workspaceId,
    required String parentRelativePath,
    required String name,
    required bool directory,
  });

  Future<native.WorkspaceFileEntry> renameEntry({
    required String workspaceId,
    required String relativePath,
    required String newName,
  });

  Future<native.WorkspaceFileEntry> copyEntry({
    required String workspaceId,
    required String relativePath,
    required String targetParentRelativePath,
  });

  Future<native.WorkspaceFileEntry> moveEntry({
    required String workspaceId,
    required String relativePath,
    required String targetParentRelativePath,
  });

  Future<void> deleteEntry({
    required String workspaceId,
    required String relativePath,
    required bool useTrash,
  });

  Future<native.WorkspaceQuickOpenSession> startQuickOpenSession({
    required String workspaceId,
  });

  Future<List<native.WorkspaceQuickOpenMatch>> searchQuickOpenSession({
    required native.WorkspaceQuickOpenSession session,
    required String query,
    required int limit,
  });

  Future<void> stopQuickOpenSession({
    required native.WorkspaceQuickOpenSession session,
  });
}

class RuntimeWorkspaceFilesClient implements RuntimeWorkspaceFiles {
  RuntimeWorkspaceFilesClient(this._client, {this.beforeAccess});

  final RuntimeHostClient _client;
  final Future<void> Function()? beforeAccess;

  @override
  Future<List<native.WorkspaceFileEntry>> listChildren({
    required String workspaceId,
    required String relativePath,
    required bool hideIgnored,
  }) async {
    await _ensureReady();
    await _ensureCapability();
    try {
      final payload = _asMap(
        await _client.runtimeRequest('workspace.files.list', <String, Object?>{
          'workspaceId': workspaceId,
          'relativePath': relativePath,
          'hideIgnored': hideIgnored,
        }),
      );
      return _entriesFromPayload(payload);
    } catch (error) {
      throw WorkspaceException(userFacingExceptionMessage(error));
    }
  }

  @override
  Future<native.WorkspaceEditorTextFile> readEditorTextFile({
    required String workspaceId,
    required String relativePath,
    required int tabSize,
  }) async {
    final file = await readTextFile(
      workspaceId: workspaceId,
      relativePath: relativePath,
    );
    return native.WorkspaceEditorTextFile(
      rawContent: file.content,
      displayContent: expandWorkspaceEditorTabs(file.content, tabSize),
      contentToken: file.contentToken,
      modifiedMillis: file.modifiedMillis,
      size: file.size,
    );
  }

  @override
  Future<native.WorkspaceEditorTextFile> writeEditorTextFile({
    required String workspaceId,
    required String relativePath,
    required String currentDisplayContent,
    required String? originalRawContent,
    required String? originalDisplayContent,
    required String? expectedContentToken,
    required bool overwriteIfChanged,
    required int tabSize,
  }) async {
    final payload = await _mutate('workspace.files.write', <String, Object?>{
      'workspaceId': workspaceId,
      'relativePath': relativePath,
      'currentDisplayContent': currentDisplayContent,
      'originalRawContent': originalRawContent,
      'originalDisplayContent': originalDisplayContent,
      'expectedContentToken': expectedContentToken,
      'overwriteIfChanged': overwriteIfChanged,
      'tabSize': tabSize,
    });
    return native.WorkspaceEditorTextFile(
      rawContent: _requiredString(payload, 'rawContent'),
      displayContent: _requiredString(payload, 'displayContent'),
      contentToken: _requiredString(payload, 'contentToken'),
      modifiedMillis: _int(payload['modifiedMillis']),
      size: BigInt.from(_int(payload['size'])),
    );
  }

  @override
  Future<native.WorkspaceTextFile> writeTextFile({
    required String workspaceId,
    required String relativePath,
    required String content,
    required String? expectedContentToken,
    required bool overwriteIfChanged,
  }) async {
    final payload = await _mutate('workspace.files.write', <String, Object?>{
      'workspaceId': workspaceId,
      'relativePath': relativePath,
      'contentBase64': base64Encode(utf8.encode(content)),
      'expectedContentToken': expectedContentToken,
      'overwriteIfChanged': overwriteIfChanged,
    });
    return native.WorkspaceTextFile(
      content: content,
      contentToken: _requiredString(payload, 'contentToken'),
      modifiedMillis: _int(payload['modifiedMillis']),
      size: BigInt.from(_int(payload['size'])),
    );
  }

  @override
  Future<native.WorkspaceFileEntry> createEntry({
    required String workspaceId,
    required String parentRelativePath,
    required String name,
    required bool directory,
  }) async {
    return _entryFromJson(
      await _mutate('workspace.files.create', <String, Object?>{
        'workspaceId': workspaceId,
        'parentRelativePath': parentRelativePath,
        'name': name,
        'kind': directory ? 'directory' : 'file',
      }),
    );
  }

  @override
  Future<native.WorkspaceFileEntry> renameEntry({
    required String workspaceId,
    required String relativePath,
    required String newName,
  }) async {
    return _entryFromJson(
      await _mutate('workspace.files.rename', <String, Object?>{
        'workspaceId': workspaceId,
        'relativePath': relativePath,
        'newName': newName,
      }),
    );
  }

  @override
  Future<native.WorkspaceFileEntry> copyEntry({
    required String workspaceId,
    required String relativePath,
    required String targetParentRelativePath,
  }) async {
    return _entryFromJson(
      await _mutate('workspace.files.copy', <String, Object?>{
        'workspaceId': workspaceId,
        'relativePath': relativePath,
        'targetParentRelativePath': targetParentRelativePath,
      }),
    );
  }

  @override
  Future<native.WorkspaceFileEntry> moveEntry({
    required String workspaceId,
    required String relativePath,
    required String targetParentRelativePath,
  }) async {
    return _entryFromJson(
      await _mutate('workspace.files.move', <String, Object?>{
        'workspaceId': workspaceId,
        'relativePath': relativePath,
        'targetParentRelativePath': targetParentRelativePath,
      }),
    );
  }

  @override
  Future<void> deleteEntry({
    required String workspaceId,
    required String relativePath,
    required bool useTrash,
  }) async {
    await _mutate('workspace.files.delete', <String, Object?>{
      'workspaceId': workspaceId,
      'relativePath': relativePath,
      'useTrash': useTrash,
    });
  }

  @override
  Future<native.WorkspaceQuickOpenSession> startQuickOpenSession({
    required String workspaceId,
  }) async {
    final payload = await _mutate(
      'mobile.workspaceQuickOpen.start',
      <String, Object?>{'workspaceId': workspaceId},
    );
    return native.WorkspaceQuickOpenSession(
      id: _requiredString(payload, 'sessionId'),
      indexedFileCount: _int(payload['indexedFileCount']),
    );
  }

  @override
  Future<List<native.WorkspaceQuickOpenMatch>> searchQuickOpenSession({
    required native.WorkspaceQuickOpenSession session,
    required String query,
    required int limit,
  }) async {
    final payload = await _mutate(
      'mobile.workspaceQuickOpen.search',
      <String, Object?>{
        'sessionId': session.id,
        'indexedFileCount': session.indexedFileCount,
        'query': query,
        'limit': limit,
      },
    );
    final items = payload['items'];
    if (items is! List) {
      return const <native.WorkspaceQuickOpenMatch>[];
    }
    return <native.WorkspaceQuickOpenMatch>[
      for (final item in items)
        if (item is Map)
          native.WorkspaceQuickOpenMatch(
            relativePath: _requiredString(
              Map<String, Object?>.from(item),
              'relativePath',
            ),
            score: _int(item['score']),
          ),
    ];
  }

  @override
  Future<void> stopQuickOpenSession({
    required native.WorkspaceQuickOpenSession session,
  }) async {
    await _ensureReady();
    try {
      await _client.runtimeRequest(
        'mobile.workspaceQuickOpen.stop',
        <String, Object?>{'sessionId': session.id},
      );
    } catch (_) {
      // Best effort: the satellite drops the index when the link closes.
    }
  }

  /// Runs a workspace-scoped verb and maps a typed `workspaceFile` conflict
  /// back into the bridge's [native.WorkspaceFileError] so Explorer and the
  /// editor react (conflict prompt, protected path) exactly as they do for a
  /// local checkout.
  Future<Map<String, Object?>> _mutate(
    String verb,
    Map<String, Object?> payload,
  ) async {
    await _ensureReady();
    await _ensureCapability();
    try {
      return _asMap(await _client.runtimeRequest(verb, payload));
    } on TerminalHostConflictException catch (error) {
      final mapped = workspaceFileErrorFromConflict(error);
      if (mapped != null) {
        throw mapped;
      }
      throw WorkspaceException(userFacingExceptionMessage(error));
    } on WorkspaceException {
      rethrow;
    } catch (error) {
      throw WorkspaceException(userFacingExceptionMessage(error));
    }
  }

  @override
  Future<native.WorkspaceTextFile> readTextFile({
    required String workspaceId,
    required String relativePath,
  }) async {
    await _ensureReady();
    await _ensureCapability();
    try {
      final read = await _readAllBytes(
        workspaceId: workspaceId,
        relativePath: relativePath,
      );
      return native.WorkspaceTextFile(
        content: utf8.decode(read.bytes),
        // Older satellites omit the token; the path keeps the buffer keyed
        // and the write then skips the conflict check instead of failing it.
        contentToken: read.contentToken ?? relativePath,
        modifiedMillis: read.modifiedMillis,
        size: BigInt.from(read.bytes.length),
      );
    } on WorkspaceException {
      rethrow;
    } on FormatException {
      throw const native.WorkspaceFileError(
        kind: native.WorkspaceFileErrorKind.unsupported,
        context: 'remote file is not text',
      );
    } catch (error) {
      throw WorkspaceException(userFacingExceptionMessage(error));
    }
  }

  Future<_RemoteRead> _readAllBytes({
    required String workspaceId,
    required String relativePath,
  }) async {
    final collected = <int>[];
    String? contentToken;
    var modifiedMillis = 0;
    var offset = 0;
    while (true) {
      final payload = _asMap(
        await _client.runtimeRequest('workspace.files.read', <String, Object?>{
          'workspaceId': workspaceId,
          'relativePath': relativePath,
          'offset': offset,
          'length': remoteWorkspaceFileReadChunkBytes,
        }),
      );
      if (payload['isText'] == false) {
        throw native.WorkspaceFileError(
          kind: native.WorkspaceFileErrorKind.unsupported,
          context: relativePath,
        );
      }
      final chunk = base64Decode(_requiredString(payload, 'dataBase64'));
      collected.addAll(chunk);
      contentToken ??= _optionalString(payload['contentToken']);
      modifiedMillis = _int(payload['modifiedMillis']);
      if (collected.length > remoteWorkspaceFileReadMaxBytes) {
        throw WorkspaceException(
          'The remote file is larger than 2 MB and cannot be opened in the editor.',
        );
      }
      final read = _RemoteRead(collected, contentToken, modifiedMillis);
      if (chunk.isEmpty) {
        return read;
      }
      final nextOffset = (payload['nextOffset'] as num?)?.toInt();
      // A missing or non-advancing nextOffset would retry the same offset
      // forever; the 2 MB cap only grows when later chunks append.
      if (nextOffset == null || nextOffset <= offset) {
        throw WorkspaceException(
          'The remote host returned an invalid file read offset. Update the sidecar, then retry.',
        );
      }
      final totalBytes = (payload['totalBytes'] as num?)?.toInt() ?? nextOffset;
      if (nextOffset >= totalBytes) {
        return read;
      }
      offset = nextOffset;
    }
  }

  Future<void> _ensureReady() async {
    await beforeAccess?.call();
  }

  Future<void> _ensureCapability() async {
    final status = _asMap(await _client.runtimeRequest('status.get'));
    final capabilities = status['runtimeCapabilities'];
    if (capabilities is! List ||
        !capabilities.contains(aleraRuntimeHostRemoteSshWorkspacesCapability)) {
      throw WorkspaceException(remoteWorkspaceFilesMissingCapabilityMessage());
    }
  }
}
