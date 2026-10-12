import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/design_system/layout/alera_collapsible_section.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_composer_controller.dart';
import 'package:alera_mobile/src/features/automations/presentation/composer/mobile_automation_composer_options.dart';
import 'package:alera_mobile/src/features/automations/presentation/composer/mobile_automation_composer_status.dart';
import 'package:alera_mobile/src/features/automations/presentation/composer/mobile_automation_prompt_field.dart';
import 'package:alera_mobile/src/features/automations/presentation/composer/mobile_automation_property_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The prompt-first body of the composer: name, prompt, one row per
/// property, the live schedule and readiness lines, then the description and
/// the options that apply.
class MobileAutomationComposerForm extends ConsumerStatefulWidget {
  const MobileAutomationComposerForm({
    super.key,
    required this.provider,
    required this.hostId,
  });

  final MobileAutomationComposerControllerProvider provider;
  final String hostId;

  @override
  ConsumerState<MobileAutomationComposerForm> createState() =>
      _MobileAutomationComposerFormState();
}

class _MobileAutomationComposerFormState
    extends ConsumerState<MobileAutomationComposerForm> {
  final GlobalKey _optionsKey = GlobalKey(debugLabel: 'automationOptions');
  late final AutomationDraft _initial = ref.read(widget.provider).draft;
  late final MobileAutomationTemplateTextController _prompt =
      MobileAutomationTemplateTextController(text: _initial.promptTemplate);
  late final TextEditingController _name = TextEditingController(
    text: _initial.name,
  );
  late final TextEditingController _description = TextEditingController(
    text: _initial.description,
  );
  late bool _optionsExpanded = _initial.customizedOptionCount > 0;

  @override
  void dispose() {
    _prompt.dispose();
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _update(AutomationDraft Function(AutomationDraft draft) change) =>
      ref.read(widget.provider.notifier).update(change);

  void _showOptions() {
    setState(() => _optionsExpanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _optionsKey.currentContext;
      if (target != null && target.mounted) {
        Scrollable.ensureVisible(
          target,
          duration: AleraTokens.durationMid,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(widget.provider);
    final draft = state.draft;
    final options = draft.customizedOptionCount;
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        AleraTextField(
          controller: _name,
          labelText: 'Name',
          hintText: draft.effectiveName,
          onChanged: (value) =>
              _update((current) => current.copyWith(name: value)),
        ),
        const SizedBox(height: AleraTokens.spaceMd),
        MobileAutomationPromptField(
          controller: _prompt,
          errorText: state.problemFor(.prompt),
          onChanged: (value) =>
              _update((current) => current.copyWith(promptTemplate: value)),
        ),
        const SizedBox(height: AleraTokens.spaceSm),
        MobileAutomationPropertyRows(
          provider: widget.provider,
          hostId: widget.hostId,
          onShowOptions: _showOptions,
        ),
        const SizedBox(height: AleraTokens.spaceSm),
        MobileAutomationComposerStatus(provider: widget.provider),
        const SizedBox(height: AleraTokens.spaceMd),
        AleraCollapsibleSection(
          title: 'Description',
          initiallyExpanded: _initial.description.isNotEmpty,
          child: AleraTextField(
            controller: _description,
            labelText: 'Description (Optional)',
            minLines: 2,
            maxLines: 4,
            onChanged: (value) =>
                _update((current) => current.copyWith(description: value)),
          ),
        ),
        AleraCollapsibleSection(
          key: _optionsKey,
          title: options == 0 ? 'Options' : 'Options · $options Changed',
          description:
              'Only the options that apply to this schedule and destination.',
          expanded: _optionsExpanded,
          onExpandedChanged: (value) =>
              setState(() => _optionsExpanded = value),
          child: MobileAutomationComposerOptions(
            provider: widget.provider,
            hostId: widget.hostId,
          ),
        ),
      ],
    );
  }
}
