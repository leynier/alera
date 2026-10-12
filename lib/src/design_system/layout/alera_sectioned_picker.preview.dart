import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_sectioned_picker.dart';
import 'package:flutter/material.dart';

@AleraPreview(
  name: 'Destinations',
  group: 'Sectioned picker',
  size: Size(460, 380),
)
Widget aleraSectionedPickerPreview() => SizedBox(
  width: AleraTokens.dialogCompactWidth,
  child: AleraSectionedPicker<String>(
    autofocus: false,
    selectedValue: 'fresh:main',
    onSelected: (_) {},
    sections: const <AleraPickerSection<String>>[
      AleraPickerSection<String>(
        title: 'Running Agents',
        emptyMessage: 'No running agents.',
        rows: <AleraPickerRow<String>>[],
      ),
      AleraPickerSection<String>(
        title: 'New Tab In A Workspace',
        rows: <AleraPickerRow<String>>[
          AleraPickerRow<String>(
            value: 'fresh:main',
            title: 'alera / main',
            subtitle: 'Local',
            leading: Icon(AleraIcons.folder, size: AleraTokens.iconMd),
          ),
          AleraPickerRow<String>(
            value: 'fresh:remote',
            title: 'alera / remote-mac',
            leading: Icon(AleraIcons.host, size: AleraTokens.iconMd),
            disabledReason: 'Host is offline.',
          ),
        ],
      ),
      AleraPickerSection<String>(
        title: 'New Worktree',
        rows: <AleraPickerRow<String>>[
          AleraPickerRow<String>(
            value: 'worktree:alera',
            title: 'alera',
            subtitle: 'From main',
            leading: Icon(AleraIcons.gitBranch, size: AleraTokens.iconMd),
          ),
        ],
      ),
    ],
  ),
);
