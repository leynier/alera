import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/badges/alera_keybinding_badge.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/chips/alera_chip.dart';
import 'package:alera/src/design_system/chips/alera_property_chip.dart';
import 'package:alera/src/design_system/feedback/alera_color_swatch.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera/src/design_system/feedback/alera_status_indicator.dart';
import 'package:alera/src/design_system/forms/alera_number_field.dart';
import 'package:alera/src/design_system/forms/alera_date_time_field.dart';
import 'package:alera/src/design_system/forms/alera_duration_field.dart';
import 'package:alera/src/design_system/forms/alera_time_of_day_field.dart';
import 'package:alera/src/design_system/forms/alera_composer.dart';
import 'package:alera/src/design_system/forms/alera_search_field.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/forms/alera_color_picker.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_collapsible_section.dart';
import 'package:alera/src/design_system/layout/alera_key_value_row.dart';
import 'package:alera/src/design_system/layout/alera_section_header.dart';
import 'package:alera/src/design_system/layout/alera_sectioned_picker.dart';
import 'package:alera/src/design_system/menus/alera_menu_item.dart';
import 'package:alera/src/design_system/surfaces/alera_command_line.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:flutter/material.dart';

/// Aggregated previews that show the whole design system grouped by category,
/// for a single-glance review of visual coherence in the widget previewer.

@AleraPreview(name: 'Buttons & chips', group: 'Gallery', size: Size(520, 200))
Widget galleryButtonsAndChips() => Wrap(
  spacing: AleraTokens.space12,
  runSpacing: AleraTokens.space12,
  crossAxisAlignment: .center,
  children: <Widget>[
    AleraIconButton(tooltip: 'Add', icon: AleraIcons.add, onPressed: () {}),
    AleraSegmentedButton<int>(
      selected: 0,
      onSelectionChanged: (_) {},
      segments: const <ButtonSegment<int>>[
        ButtonSegment<int>(value: 0, icon: Icon(AleraIcons.square)),
        ButtonSegment<int>(value: 1, icon: Icon(AleraIcons.text)),
      ],
    ),
    const AleraBadge(label: 'Primary'),
    const AleraBadge(label: 'Needs Input', tone: .attention),
    const AleraBadge(label: 'Done', tone: .success),
    const AleraKeybindingBadge(label: 'Ctrl+Shift+P'),
    const AleraChip(label: 'Alera'),
    const AleraChip(
      label: '#frontend',
      leading: AleraIcons.tag,
      tooltip: 'frontend',
    ),
    AleraChip(label: 'Removable', onRemove: () {}),
  ],
);

@AleraPreview(name: 'Inputs', group: 'Gallery', size: Size(420, 260))
Widget galleryInputs() => Column(
  mainAxisSize: .min,
  crossAxisAlignment: .stretch,
  children: <Widget>[
    const AleraTextField(hintText: 'Workspace name'),
    const SizedBox(height: AleraTokens.space12),
    const AleraSearchField(hintText: 'Search'),
    const SizedBox(height: AleraTokens.space12),
    AleraNumberField(
      value: 13,
      min: 8,
      max: 32,
      step: 1,
      suffix: 'px',
      onChanged: (_) {},
    ),
  ],
);

@AleraPreview(name: 'Composer', group: 'Gallery', size: Size(560, 180))
Widget galleryComposer() => const _GalleryComposer();

class const _GalleryComposer() extends StatefulWidget {
  @override
  State<_GalleryComposer> createState() => _GalleryComposerState();
}

class _GalleryComposerState extends State<_GalleryComposer> {
  final _controller = TextEditingController(text: 'Explain the failing test');
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AleraComposer(
      controller: _controller,
      focusNode: _focusNode,
      onSend: _controller.clear,
      onClose: () {},
      textActions: const <AleraTextActionMenuItem>[
        AleraTextActionMenuItem(id: 'concise', label: 'Make Concise'),
      ],
      onTextActionSelected: (_) {},
    );
  }
}

@AleraPreview(name: 'Feedback', group: 'Gallery', size: Size(420, 240))
Widget galleryFeedback() => Column(
  mainAxisSize: .min,
  children: <Widget>[
    Row(
      mainAxisAlignment: .center,
      children: <Widget>[
        const AleraStatusDot(active: true),
        const SizedBox(width: AleraTokens.space12),
        const AleraStatusDot(active: false),
        const SizedBox(width: AleraTokens.space12),
        const AleraStatusIndicator(
          icon: AleraIcons.check,
          color: AleraTokens.success,
        ),
        const SizedBox(width: AleraTokens.space12),
        const AleraColorSwatch(color: AleraTokens.info),
      ],
    ),
    const SizedBox(height: AleraTokens.space24),
    const AleraEmptyState(icon: AleraIcons.searchOff, message: 'No results.'),
  ],
);

@AleraPreview(name: 'Surfaces & layout', group: 'Gallery', size: Size(560, 240))
Widget gallerySurfaces() => Column(
  mainAxisSize: .min,
  crossAxisAlignment: .stretch,
  children: <Widget>[
    const AleraSectionHeader(
      label: 'Workspace',
      leadingIcon: AleraIcons.folder,
    ),
    const SizedBox(height: AleraTokens.space8),
    const AleraPanel(
      children: <Widget>[
        AleraSettingRow(
          title: 'Confirm before closing',
          description: 'Ask for confirmation when closing a workspace.',
          child: Switch(value: true, onChanged: null),
        ),
        AleraSettingRow(
          title: 'Restore previous session',
          child: Switch(value: false, onChanged: null),
        ),
      ],
    ),
    const SizedBox(height: AleraTokens.space12),
    const AleraCommandLine(command: 'sudo dnf upgrade alera'),
  ],
);

@AleraPreview(name: 'Menu', group: 'Gallery', size: Size(280, 140))
Widget galleryMenu() => Material(
  color: AleraTokens.surfaceElevated,
  borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
  child: Padding(
    padding: const EdgeInsets.all(AleraTokens.space8),
    child: Column(
      mainAxisSize: .min,
      children: <Widget>[
        AleraMenuItem(label: 'Solarized Dark', selected: true, onTap: () {}),
        AleraMenuItem(label: 'Dracula', selected: false, onTap: () {}),
        AleraMenuItem(
          label: 'Gruvbox',
          selected: false,
          active: true,
          onTap: () {},
        ),
      ],
    ),
  ),
);

@AleraPreview(name: 'Color picker', group: 'Gallery', size: Size(300, 285))
Widget galleryColorPicker() => Center(
  child: AleraColorPicker(
    pickerColor: AleraTokens.info,
    onColorChanged: (_) {},
  ),
);

@AleraPreview(name: 'Composer controls', group: 'Gallery', size: Size(560, 640))
Widget galleryComposerControls() => SingleChildScrollView(
  child: Column(
    mainAxisSize: .min,
    crossAxisAlignment: .stretch,
    children: <Widget>[
      Wrap(
        spacing: AleraTokens.space8,
        runSpacing: AleraTokens.space8,
        children: <Widget>[
          AleraPropertyChip(
            icon: AleraIcons.schedule,
            value: 'Weekdays at 09:00',
            onTap: () {},
          ),
          AleraPropertyChip(
            icon: AleraIcons.folder,
            value: 'alera / main',
            fromContext: true,
            onTap: () {},
          ),
          AleraPropertyChip(
            icon: AleraIcons.agent,
            value: 'Choose Agent',
            hasError: true,
            onTap: () {},
          ),
        ],
      ),
      const SizedBox(height: AleraTokens.space16),
      AleraDurationField(
        labelText: 'Inactivity Timeout',
        seconds: 900,
        onChanged: (_) {},
      ),
      const SizedBox(height: AleraTokens.space12),
      AleraTimeOfDayField(
        labelText: 'Time',
        hour: 9,
        minute: 0,
        onChanged: (_, _) {},
      ),
      const SizedBox(height: AleraTokens.space12),
      AleraDateTimeField(
        labelText: 'Starts',
        value: DateTime(2026, 10, 13, 9),
        clearable: true,
        onChanged: (_) {},
      ),
      const SizedBox(height: AleraTokens.space12),
      const AleraCollapsibleSection(
        title: 'Options',
        initiallyExpanded: true,
        child: Column(
          children: <Widget>[
            AleraKeyValueRow(label: 'Retry Attempts', value: '2'),
            AleraKeyValueRow(label: 'Notify On Success', value: 'Off'),
          ],
        ),
      ),
      const SizedBox(height: AleraTokens.space12),
      AleraPanel(
        children: <Widget>[
          AleraSectionedPicker<String>(
            autofocus: false,
            searchable: false,
            selectedValue: 'main',
            onSelected: (_) {},
            sections: const <AleraPickerSection<String>>[
              AleraPickerSection<String>(
                title: 'New Tab In A Workspace',
                rows: <AleraPickerRow<String>>[
                  AleraPickerRow<String>(value: 'main', title: 'alera / main'),
                  AleraPickerRow<String>(
                    value: 'docs',
                    title: 'alera / docs',
                    disabledReason: 'Host is offline.',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  ),
);
