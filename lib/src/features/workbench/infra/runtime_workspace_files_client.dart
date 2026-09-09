import 'dart:convert';

import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;

const int remoteWorkspaceFileReadChunkBytes = 256 * 1024;
const int remoteWorkspaceFileReadMaxBytes = 2 * 1024 * 1024;

abstract interface class RuntimeWorkspaceFiles {
  Future<List<native.WorkspaceFileEntry>> listChildren({
    required String workspaceId,
    required String relativePath,
    required bool hideIgnored,
  });

  Future<native.WorkspaceEditorTextFile> readEditorTextFile({
    required String workspaceId,
    required String relativePath,
  });

  Future<native.WorkspaceTextFile> readTextFile({
    required String workspaceId,
    required String relativePath,
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
  }) async {
    final file = await readTextFile(
      workspaceId: workspaceId,
      relativePath: relativePath,
    );
    return native.WorkspaceEditorTextFile(
      rawContent: file.content,
      displayContent: file.content,
      contentToken: file.contentToken,
      modifiedMillis: file.modifiedMillis,
      size: file.size,
    );
  }

  @override
  Future<native.WorkspaceTextFile> readTextFile({
    required String workspaceId,
    required String relativePath,
  }) async {
    await _ensureReady();
    await _ensureCapability();
    try {
      final bytes = await _readAllBytes(
        workspaceId: workspaceId,
        relativePath: relativePath,
      );
      return native.WorkspaceTextFile(
        content: utf8.decode(bytes),
        contentToken: relativePath,
        modifiedMillis: 0,
        size: BigInt.from(bytes.length),
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

  Future<List<int>> _readAllBytes({
    required String workspaceId,
    required String relativePath,
  }) async {
    final collected = <int>[];
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
      if (collected.length > remoteWorkspaceFileReadMaxBytes) {
        throw WorkspaceException(
          'The remote file is larger than 2 MB and cannot be opened in the editor.',
        );
      }
      if (chunk.isEmpty) {
        return collected;
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
        return collected;
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

List<native.WorkspaceFileEntry> _entriesFromPayload(Map<String, Object?> json) {
  final entries = json['entries'];
  if (entries is! List) {
    return const <native.WorkspaceFileEntry>[];
  }
  return <native.WorkspaceFileEntry>[
    for (final item in entries)
      if (item is Map) _entryFromJson(Map<String, Object?>.from(item)),
  ];
}

native.WorkspaceFileEntry _entryFromJson(Map<String, Object?> json) {
  final name = _requiredString(json, 'name');
  final relativePath = _optionalString(json['relativePath']) ?? name;
  final kind = _fileKind(json['kind']);
  return native.WorkspaceFileEntry(
    relativePath: relativePath,
    name: name,
    kind: kind,
    size: BigInt.from((json['size'] as num?)?.toInt() ?? 0),
    modifiedMillis: 0,
    contentToken: relativePath,
    isIgnored: json['isIgnored'] == true,
    isHidden: json['isHidden'] == true,
    isSymlink: kind == native.WorkspaceFileKind.symlink,
    isProtected: json['isProtected'] == true,
    hasChildrenHint: json['hasChildrenHint'] == true,
  );
}

native.WorkspaceFileKind _fileKind(Object? value) {
  return switch (value) {
    'directory' => native.WorkspaceFileKind.directory,
    'symlink' => native.WorkspaceFileKind.symlink,
    'other' => native.WorkspaceFileKind.other,
    _ => native.WorkspaceFileKind.file,
  };
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  throw const FormatException(
    'Runtime workspace files payload must be a JSON object.',
  );
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw FormatException('$key must be a non-empty string.');
}

String? _optionalString(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  return null;
}
