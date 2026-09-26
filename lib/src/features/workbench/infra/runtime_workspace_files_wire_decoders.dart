part of 'runtime_workspace_files_client.dart';

/// Decoders for the JSON the runtime's `workspace.files.*` verbs answer with,
/// and the typed file error they carry, rebuilt as the bridge's own types so a
/// remote checkout reads the same as a local one.

class const _RemoteRead(
  final List<int> bytes,
  final String? contentToken,
  final int modifiedMillis,
);

/// Rebuilds the bridge's file error from the runtime's typed conflict, or
/// returns null when the conflict is about something else.
native.WorkspaceFileError? workspaceFileErrorFromConflict(
  TerminalHostConflictException error,
) {
  if (error.code != runtimeWorkspaceFileErrorCode) {
    return null;
  }
  final kind = switch (error.details['kind']) {
    'invalidPath' => native.WorkspaceFileErrorKind.invalidPath,
    'outsideWorkspace' => native.WorkspaceFileErrorKind.outsideWorkspace,
    'notFound' => native.WorkspaceFileErrorKind.notFound,
    'alreadyExists' => native.WorkspaceFileErrorKind.alreadyExists,
    'protectedPath' => native.WorkspaceFileErrorKind.protectedPath,
    'unsupported' => native.WorkspaceFileErrorKind.unsupported,
    'conflict' => native.WorkspaceFileErrorKind.conflict,
    _ => native.WorkspaceFileErrorKind.io,
  };
  return native.WorkspaceFileError(
    kind: kind,
    context: _optionalString(error.details['context']) ?? error.message,
  );
}

/// Mirrors the bridge's tab expansion for a buffer the desktop did not read
/// through the bridge. Columns reset on every line break; tab size is
/// clamped to 1..8 like the native codec.
String expandWorkspaceEditorTabs(String text, int tabSize) {
  final width = tabSize.clamp(1, 8);
  final buffer = StringBuffer();
  var column = 0;
  for (final rune in text.runes) {
    if (rune == 0x09) {
      final spaces = width - (column % width);
      buffer.write(' ' * spaces);
      column += spaces;
      continue;
    }
    buffer.writeCharCode(rune);
    if (rune == 0x0A || rune == 0x0D) {
      column = 0;
    } else {
      column += 1;
    }
  }
  return buffer.toString();
}

int _int(Object? value) => value is num ? value.toInt() : 0;

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
    size: BigInt.from(_int(json['size'])),
    modifiedMillis: _int(json['modifiedMillis']),
    contentToken: _optionalString(json['contentToken']) ?? relativePath,
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
