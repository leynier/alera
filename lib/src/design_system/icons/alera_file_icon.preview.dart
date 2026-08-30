import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Files', group: 'File icon')
Widget aleraFileIconFilesPreview() => const Row(
  mainAxisSize: .min,
  children: <Widget>[
    AleraFileIcon(pathOrName: 'pubspec.yaml', kind: .file),
    SizedBox(width: AleraTokens.space12),
    AleraFileIcon(pathOrName: 'lib/main.dart', kind: .file),
    SizedBox(width: AleraTokens.space12),
    AleraFileIcon(pathOrName: '.gitignore', kind: .file),
  ],
);

@AleraPreview(name: 'Folders', group: 'File icon')
Widget aleraFileIconFoldersPreview() => const Row(
  mainAxisSize: .min,
  children: <Widget>[
    AleraFileIcon(pathOrName: 'src', kind: .folder),
    SizedBox(width: AleraTokens.space12),
    AleraFileIcon(pathOrName: '.vscode', kind: .folder, isExpanded: true),
    SizedBox(width: AleraTokens.space12),
    AleraFileIcon(pathOrName: 'assets', kind: .folder),
  ],
);
