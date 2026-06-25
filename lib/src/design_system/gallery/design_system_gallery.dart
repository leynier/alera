import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/chips/alera_chip.dart';
import 'package:alera/src/design_system/feedback/alera_color_swatch.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera/src/design_system/feedback/alera_status_indicator.dart';
import 'package:alera/src/design_system/forms/alera_number_field.dart';
import 'package:alera/src/design_system/forms/alera_search_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/forms/alera_color_picker.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_section_header.dart';
import 'package:alera/src/design_system/menus/alera_menu_item.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:flutter/material.dart';

/// Aggregated previews that show the whole design system grouped by category,
/// for a single-glance review of visual coherence in the widget previewer.

@AleraPreview(name: 'Buttons & chips', group: 'Gallery', size: Size(520, 200))
Widget galleryButtonsAndChips() => Wrap(
  spacing: AleraTokens.space12,
  runSpacing: AleraTokens.space12,
  crossAxisAlignment: WrapCrossAlignment.center,
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
    const AleraChip(label: 'Alera'),
    AleraChip(label: 'Removable', onRemove: () {}),
  ],
);

@AleraPreview(name: 'Inputs', group: 'Gallery', size: Size(420, 260))
Widget galleryInputs() => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: <Widget>[
    const AleraTextField(hintText: 'Workspace Name'),
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

@AleraPreview(name: 'Feedback', group: 'Gallery', size: Size(420, 240))
Widget galleryFeedback() => Column(
  mainAxisSize: MainAxisSize.min,
  children: <Widget>[
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
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
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.stretch,
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
  ],
);

@AleraPreview(name: 'Menu', group: 'Gallery', size: Size(280, 140))
Widget galleryMenu() => Material(
  color: AleraTokens.surfaceElevated,
  borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
  child: Padding(
    padding: const EdgeInsets.all(AleraTokens.space8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
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
