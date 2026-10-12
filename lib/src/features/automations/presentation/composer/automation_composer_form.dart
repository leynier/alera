import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_collapsible_section.dart';
import 'package:alera/src/features/automations/application/automation_composer_controller.dart';
import 'package:alera/src/features/automations/presentation/composer/automation_composer_chips.dart';
import 'package:alera/src/features/automations/presentation/composer/automation_composer_options.dart';
import 'package:alera/src/features/automations/presentation/composer/automation_composer_status.dart';
import 'package:alera/src/features/automations/presentation/composer/automation_prompt_editor.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The prompt-first body of the composer: name, prompt, one chip per
/// property, the live schedule and readiness lines, then the description and
/// the options that apply.
class AutomationComposerForm extends ConsumerStatefulWidget {
  const AutomationComposerForm({
    super.key,
    required this.provider,
    this.onSubmit,
  });

  final AutomationComposerControllerProvider provider;

  /// The primary action, for Control+Enter or Cmd+Enter in the prompt.
  final VoidCallback? onSubmit;

  @override
  ConsumerState<AutomationComposerForm> createState() =>
      _AutomationComposerFormState();
}

class _AutomationComposerFormState
    extends ConsumerState<AutomationComposerForm> {
  final GlobalKey _optionsKey = GlobalKey(debugLabel: 'automationOptions');
  late final AutomationDraft _initial = ref.read(widget.provider).draft;
  late final AutomationTemplateTextController _prompt =
      AutomationTemplateTextController(text: _initial.promptTemplate);
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
    final flagged = state.flaggedProperties;
    final promptIssue = state.readiness?.errors
        .where(
          (issue) =>
              automationIssueProperty(issue) ==
              AutomationComposerProperty.prompt,
        )
        .firstOrNull
        ?.message;
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
        const SizedBox(height: AleraTokens.space12),
        AutomationPromptEditor(
          controller: _prompt,
          autofocus: true,
          errorText: flagged.contains(AutomationComposerProperty.prompt)
              ? (state.showErrors ? draft.whatError : null) ?? promptIssue
              : null,
          onCommandEnter: widget.onSubmit,
          onChanged: (value) =>
              _update((current) => current.copyWith(promptTemplate: value)),
        ),
        const SizedBox(height: AleraTokens.space12),
        AutomationComposerChips(
          provider: widget.provider,
          onShowOptions: _showOptions,
        ),
        const SizedBox(height: AleraTokens.space12),
        AutomationComposerStatus(provider: widget.provider),
        const SizedBox(height: AleraTokens.space12),
        AleraCollapsibleSection(
          title: 'Description',
          initiallyExpanded: _initial.description.isNotEmpty,
          child: Padding(
            padding: const EdgeInsets.only(top: AleraTokens.space8),
            child: AleraTextField(
              controller: _description,
              labelText: 'Description (Optional)',
              minLines: 2,
              maxLines: 4,
              onChanged: (value) =>
                  _update((current) => current.copyWith(description: value)),
            ),
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
          child: Padding(
            padding: const EdgeInsets.only(top: AleraTokens.space8),
            child: AutomationComposerOptions(provider: widget.provider),
          ),
        ),
      ],
    );
  }
}
