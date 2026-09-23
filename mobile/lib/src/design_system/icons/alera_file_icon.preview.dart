import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/alera_preview.dart';
import 'package:alera_mobile/src/design_system/icons/alera_file_icon.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Files', group: 'File Icon')
Widget aleraFileIconFilesPreview() => const Row(
  mainAxisSize: .min,
  children: <Widget>[
    AleraFileIcon(pathOrName: 'pubspec.yaml', kind: .file),
    SizedBox(width: AleraTokens.space12),
    AleraFileIcon(pathOrName: 'lib/main.dart', kind: .file),
    SizedBox(width: AleraTokens.space12),
    AleraFileIcon(pathOrName: 'rust/src/lib.rs', kind: .file),
    SizedBox(width: AleraTokens.space12),
    AleraFileIcon(pathOrName: '.gitignore', kind: .file),
  ],
);

@AleraPreview(name: 'Folders', group: 'File Icon')
Widget aleraFileIconFoldersPreview() => const Row(
  mainAxisSize: .min,
  children: <Widget>[
    AleraFileIcon(pathOrName: 'src', kind: .folder),
    SizedBox(width: AleraTokens.space12),
    AleraFileIcon(pathOrName: 'src', kind: .folder, isExpanded: true),
    SizedBox(width: AleraTokens.space12),
    AleraFileIcon(pathOrName: 'link', kind: .symlink),
    SizedBox(width: AleraTokens.space12),
    AleraFileIcon(pathOrName: 'socket', kind: .generic),
  ],
);
