import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/features/automations/application/automation_authoring_controller.dart';
import 'package:alera/src/features/automations/application/automation_providers.dart';
import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/automations/domain/automation_draft.dart';
import 'package:alera/src/features/automations/domain/automation_json_fields.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/presentation/authoring/automation_authoring_review_step.dart';
import 'package:alera/src/features/automations/presentation/authoring/automation_authoring_what_when_steps.dart';
import 'package:alera/src/features/automations/presentation/authoring/automation_authoring_where_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

int _nextAuthoringSession = 0;

/// Opens the four-step flow. Returns the saved definition, which the page
/// then selects.
Future<AutomationRecord?> showAutomationAuthoringDialog(
  BuildContext context,
  WidgetRef ref, {
  AutomationAuthoringRequest request = const AutomationAuthoringRequest(),
}) async {
  final catalog =
      ref.read(automationCatalogProvider).value ?? const <AutomationRecord>[];
  AutomationRecord? find(String? id) =>
      catalog.where((item) => item.id == id).firstOrNull;
  final editing = find(request.editId);
  final cloned = find(request.cloneId);
  final template = request.template;
  final draft = editing != null
      ? AutomationDraft.fromRecord(editing)
      : cloned != null
      ? AutomationDraft.fromRecord(cloned).cloned()
      : AutomationDraft(
          originWorkspaceId: request.originWorkspaceId,
          name: automationJsonString(template?['name']),
          description: automationJsonString(template?['description']),
          promptTemplate: automationJsonString(template?['promptTemplate']),
          tagIds: automationJsonStringList(template?['tagIds']),
        );
  final session = _nextAuthoringSession++;
  final saved = await showDialog<AutomationRecord>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AutomationAuthoringDialog(
      session: session,
      request: request,
      initialDraft: draft,
      editing: editing,
    ),
  );
  if (saved != null) {
    ref.read(automationsNavigationProvider.notifier)
      ..open()
      ..select(saved.id);
    ref.invalidate(automationCatalogProvider);
  }
  return saved;
}

class AutomationAuthoringDialog extends ConsumerStatefulWidget {
  const AutomationAuthoringDialog({
    super.key,
    required this.session,
    required this.request,
    required this.initialDraft,
    this.editing,
  });

  final int session;
  final AutomationAuthoringRequest request;
  final AutomationDraft initialDraft;
  final AutomationRecord? editing;

  @override
  ConsumerState<AutomationAuthoringDialog> createState() =>
      _AutomationAuthoringDialogState();
}

class _AutomationAuthoringDialogState
    extends ConsumerState<AutomationAuthoringDialog> {
  late final AutomationAuthoringControllerProvider _provider =
      automationAuthoringControllerProvider(widget.session);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(_provider.notifier)
          .initialize(widget.initialDraft, editing: widget.editing);
      unawaited(ref.read(_provider.notifier).refreshPreview());
    });
  }

  Future<void> _submit({bool asDraft = false}) async {
    final controller = ref.read(_provider.notifier);
    final editing = widget.editing;
    final saved = await controller.submit(asDraft: asDraft);
    if (saved == null || !mounted) return;
    AleraToast.publish(
      message: editing != null
          ? 'Changes saved.'
          : asDraft
          ? 'Saved as a draft. Activate it when ready.'
          : saved.state == 'active'
          ? 'Automation created and active.'
          : 'Automation created.',
      tone: AleraToastTone.success,
    );
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    final controller = ref.read(_provider.notifier);
    final editing = widget.editing;
    final step = state.step;
    final last = step == AutomationAuthoringStep.review;
    final stepError = state.showErrors ? state.stepError(step) : null;
    final body = !state.initialized
        ? const Center(child: CircularProgressIndicator())
        : switch (step) {
            AutomationAuthoringStep.what => AutomationWhatStep(
              provider: _provider,
            ),
            AutomationAuthoringStep.when => AutomationWhenStep(
              provider: _provider,
            ),
            AutomationAuthoringStep.where => AutomationWhereStep(
              provider: _provider,
              request: widget.request,
            ),
            AutomationAuthoringStep.review => AutomationReviewStep(
              provider: _provider,
            ),
          };
    return AleraDialog(
      maxWidth: AleraTokens.automationAuthoringWidth,
      maxHeight: AleraTokens.automationAuthoringMaxHeight,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          crossAxisAlignment: .stretch,
          children: <Widget>[
            AleraDialogHeader(
              title: editing == null ? 'New Automation' : 'Edit Automation',
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: AleraTokens.space12),
            Wrap(
              spacing: AleraTokens.space4,
              children: <Widget>[
                for (final item in AutomationAuthoringStep.values)
                  TextButton(
                    onPressed: () => controller.goTo(item),
                    style: TextButton.styleFrom(
                      foregroundColor: item == step
                          ? AleraTokens.foreground
                          : AleraTokens.foregroundMuted,
                    ),
                    child: Text('${item.index + 1}. ${item.label}'),
                  ),
              ],
            ),
            const Divider(height: AleraTokens.space16),
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.only(right: AleraTokens.space8),
                  child: body,
                ),
              ),
            ),
            if (stepError ?? state.error case final message?) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              Text(
                message,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AleraTokens.error),
              ),
            ],
            const SizedBox(height: AleraTokens.space12),
            Row(
              children: <Widget>[
                if (step != AutomationAuthoringStep.what)
                  TextButton(
                    onPressed: controller.back,
                    child: const Text('Back'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                if (last && editing == null) ...<Widget>[
                  const SizedBox(width: AleraTokens.space8),
                  OutlinedButton(
                    onPressed: state.submitting
                        ? null
                        : () => unawaited(_submit(asDraft: true)),
                    child: const Text('Save As Draft'),
                  ),
                ],
                const SizedBox(width: AleraTokens.space8),
                FilledButton(
                  onPressed: state.submitting
                      ? null
                      : last
                      ? () => unawaited(_submit())
                      : controller.next,
                  child: Text(
                    !last
                        ? 'Continue'
                        : editing == null
                        ? 'Create Automation'
                        : 'Save Changes',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
