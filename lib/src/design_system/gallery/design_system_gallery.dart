import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/badges/alera_attention_chip.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/badges/alera_keybinding_badge.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/buttons/alera_tab_strip.dart';
import 'package:alera/src/design_system/chat/alera_message_bubble.dart';
import 'package:alera/src/design_system/chips/alera_chip.dart';
import 'package:alera/src/design_system/feedback/alera_color_swatch.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_gate_card.dart';
import 'package:alera/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera/src/design_system/feedback/alera_status_indicator.dart';
import 'package:alera/src/design_system/forms/alera_number_field.dart';
import 'package:alera/src/design_system/forms/alera_composer.dart';
import 'package:alera/src/design_system/forms/alera_search_field.dart';
import 'package:alera/src/design_system/forms/alera_segmented_choice.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/forms/alera_color_picker.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_rail.dart';
import 'package:alera/src/design_system/layout/alera_section_header.dart';
import 'package:alera/src/design_system/lists/alera_activity_row.dart';
import 'package:alera/src/design_system/lists/alera_key_value_list.dart';
import 'package:alera/src/design_system/lists/alera_timeline.dart';
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

@AleraPreview(name: 'Navigation', group: 'Gallery', size: Size(320, 240))
Widget galleryNavigation() => Row(
  mainAxisSize: .min,
  crossAxisAlignment: .start,
  children: <Widget>[
    AleraRail(
      items: const <AleraRailItem>[
        AleraRailItem(
          icon: AleraIcons.workspaceChildren,
          label: 'Runs',
          count: 3,
          tone: .attention,
        ),
        AleraRailItem(icon: AleraIcons.inbox, label: 'Questions', count: 2),
        AleraRailItem(icon: AleraIcons.checks, label: 'Automations'),
      ],
      selectedIndex: 0,
      onSelected: (_) {},
    ),
    const SizedBox(width: AleraTokens.space24),
    AleraAttentionChip(
      icon: AleraIcons.workspaceChildren,
      count: 5,
      tone: .warning,
      tooltip: 'Open Activity · 5 items need attention',
      onPressed: () {},
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

@AleraPreview(name: 'Messages', group: 'Gallery', size: Size(560, 320))
Widget galleryMessages() => Column(
  mainAxisSize: .min,
  crossAxisAlignment: .stretch,
  children: <Widget>[
    const AleraMessageBubble(
      heading: 'Question · ext:user',
      body: 'Which auth flow do you want for the CLI: device code or PKCE?',
      outgoing: true,
      statusLabel: 'Answered',
      statusTone: .success,
      timestamp: '14:10',
    ),
    const AleraMessageBubble(
      heading: 'Reply · Codex',
      body: 'Device code. PKCE needs a browser on the same machine.',
      outgoing: false,
      isNew: true,
      timestamp: '14:12',
    ),
    AleraSegmentedChoice<int>(
      label: 'Deliver',
      selected: 0,
      onChanged: (_) {},
      options: const <AleraSegmentedChoiceOption<int>>[
        AleraSegmentedChoiceOption<int>(
          value: 0,
          label: 'Now',
          helper:
              "The question is pasted into the agent's terminal right away.",
        ),
        AleraSegmentedChoiceOption<int>(
          value: 1,
          label: 'When the Agent Finishes Its Turn',
          helper: 'The agent receives the question when it finishes its turn.',
        ),
      ],
    ),
  ],
);

@AleraPreview(name: 'Runs', group: 'Gallery', size: Size(600, 640))
Widget galleryRuns() => Column(
  mainAxisSize: .min,
  crossAxisAlignment: .stretch,
  spacing: AleraTokens.space12,
  children: <Widget>[
    AleraActivityRow(
      title: 'Add reviewed workflow plans',
      subtitle: 'Attention · 1 Pending Gate',
      trailing: '2h ago',
      statusColor: AleraTokens.warning,
      selected: true,
      onPressed: () {},
    ),
    AleraTabStrip<int>(
      items: const <AleraTabStripItem<int>>[
        AleraTabStripItem<int>(value: 0, label: 'Overview'),
        AleraTabStripItem<int>(value: 1, label: 'Tasks', badge: '4/9'),
        AleraTabStripItem<int>(value: 2, label: 'Timeline', badge: '6'),
      ],
      selected: 1,
      onSelected: (_) {},
    ),
    const AleraKeyValueList(
      entries: <AleraKeyValue>[
        AleraKeyValue(label: 'Workflow', value: 'feature-delivery'),
        AleraKeyValue(
          label: 'Run Id',
          value: 'run_01J9ZK4Q7M2V8S3T',
          mono: true,
          copyable: true,
        ),
      ],
    ),
    AleraGateCard(
      kindLabel: 'Stage Gate',
      title: 'Foundation',
      statusLabel: 'Pending',
      statusDetail: 'Asked 2h ago',
      prompt: 'The foundation stage finished. Approve to start the next stage.',
      options: const <AleraGateCardOption>[
        AleraGateCardOption(id: 'changes', label: 'Request Changes'),
        AleraGateCardOption(id: 'approve', label: 'Approve', primary: true),
      ],
      onSelected: (_, _) {},
    ),
    SizedBox(
      height: AleraTokens.activityLogHeight,
      child: AleraTimeline(
        entries: <AleraTimelineEntry>[
          AleraTimelineEntry(
            id: 'question',
            day: 'Today',
            time: '14:02',
            title: 'The worker asked which auth flow the CLI should use',
            open: true,
            actions: <Widget>[
              TextButton(onPressed: () {}, child: const Text('Resolve')),
            ],
          ),
          const AleraTimelineEntry(
            id: 'stage',
            day: 'Today',
            time: '13:58',
            title: 'Stage Foundation passed its gate',
          ),
        ],
      ),
    ),
  ],
);
