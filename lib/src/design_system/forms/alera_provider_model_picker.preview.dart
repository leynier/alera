import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/forms/alera_provider_model_picker.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_sectioned_picker.dart';
import 'package:alera/src/design_system/surfaces/alera_popover.dart';
import 'package:flutter/material.dart';

const List<AleraPickerSection<String>> _sections = <AleraPickerSection<String>>[
  AleraPickerSection<String>(
    title: 'Codex',
    rows: <AleraPickerRow<String>>[
      AleraPickerRow<String>(
        value: 'codex:',
        title: 'Provider Default',
        leading: Icon(AleraIcons.agent, size: AleraTokens.iconMd),
      ),
      AleraPickerRow<String>(
        value: 'codex:gpt-large',
        title: 'GPT Large',
        subtitle: 'gpt-large',
        leading: Icon(AleraIcons.agent, size: AleraTokens.iconMd),
      ),
    ],
  ),
  AleraPickerSection<String>(
    title: 'Claude',
    rows: <AleraPickerRow<String>>[
      AleraPickerRow<String>(
        value: 'claude:',
        title: 'Provider Default',
        leading: Icon(AleraIcons.agent, size: AleraTokens.iconMd),
        disabledReason: 'Sign in to Claude first.',
      ),
    ],
  ),
];

@AleraPreview(
  name: 'Closed',
  group: 'Provider model picker',
  size: Size(360, 120),
)
Widget aleraProviderModelPickerPreview() => AleraProviderModelPicker<String>(
  label: 'GPT Large',
  leading: const Icon(AleraIcons.agent, size: AleraTokens.iconMd),
  sections: _sections,
  selectedValue: 'codex:gpt-large',
  tooltip: 'Choose Model',
  footerActionLabel: 'Open Provider Settings',
  onFooterAction: () {},
  onSelected: (_) {},
);

@AleraPreview(
  name: 'Loading',
  group: 'Provider model picker',
  size: Size(360, 120),
)
Widget aleraProviderModelPickerLoadingPreview() =>
    AleraProviderModelPicker<String>(
      label: 'Codex',
      leading: const Icon(AleraIcons.agent, size: AleraTokens.iconMd),
      sections: const <AleraPickerSection<String>>[],
      loading: true,
      tooltip: 'Loading agents…',
      onSelected: (_) {},
    );

@AleraPreview(
  name: 'Narrow',
  group: 'Provider model picker',
  size: Size(360, 120),
)
Widget aleraProviderModelPickerNarrowPreview() => Align(
  alignment: Alignment.centerLeft,
  child: SizedBox(
    width: AleraTokens.contextMenuWidth / 2,
    child: Row(
      children: <Widget>[
        Flexible(
          child: AleraProviderModelPicker<String>(
            label: 'GPT Large Extended Context',
            leading: const Icon(AleraIcons.agent, size: AleraTokens.iconMd),
            sections: _sections,
            selectedValue: 'codex:gpt-large',
            shrinkLabel: true,
            tooltip: 'GPT Large Extended Context · Choose Model',
            onSelected: (_) {},
          ),
        ),
      ],
    ),
  ),
);

@AleraPreview(
  name: 'Open',
  group: 'Provider model picker',
  size: Size(480, 460),
)
Widget aleraProviderModelPickerOpenPreview() => Align(
  alignment: Alignment.topLeft,
  child: AleraProviderModelPicker<String>(
    label: 'GPT Large',
    leading: const Icon(AleraIcons.agent, size: AleraTokens.iconMd),
    sections: _sections,
    selectedValue: 'codex:gpt-large',
    controller: AleraPopoverController()..open(),
    footerActionLabel: 'Open Provider Settings',
    onFooterAction: () {},
    onSelected: (_) {},
  ),
);
