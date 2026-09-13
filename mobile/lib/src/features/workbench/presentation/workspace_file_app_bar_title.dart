import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_file_icon.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_path_display.dart';
import 'package:flutter/material.dart';

/// File viewer and diff viewer app bar title: file-type icon plus basename.
class const WorkspaceFileAppBarTitle(final String path, {super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        AleraFileIcon(pathOrName: path, kind: .file),
        const SizedBox(width: AleraTokens.space8),
        Flexible(child: Text(workspaceFileBaseName(path), overflow: .ellipsis)),
      ],
    );
  }
}
