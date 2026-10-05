import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_authoring_controller.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_draft.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_json_fields.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_models.dart';
import 'package:alera_mobile/src/features/automations/presentation/authoring/mobile_automation_authoring_steps.dart';
import 'package:alera_mobile/src/features/automations/presentation/authoring/mobile_automation_where_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

int _nextSession = 0;

/// Opens the four-step flow as a full screen. Returns the saved definition.
Future<AutomationRecord?> showMobileAutomationAuthoring(
  BuildContext context, {
  required String hostId,
  String? originWorkspaceId,
  AutomationRecord? editing,
  AutomationRecord? cloneOf,
  JsonMap? template,
}) {
  final draft = editing != null
      ? AutomationDraft.fromRecord(editing)
      : cloneOf != null
      ? AutomationDraft.fromRecord(cloneOf).cloned()
      : AutomationDraft(
          originWorkspaceId: originWorkspaceId,
          name: automationJsonString(template?['name']),
          description: automationJsonString(template?['description']),
          promptTemplate: automationJsonString(template?['promptTemplate']),
          tagIds: automationJsonStringList(template?['tagIds']),
        );
  return Navigator.of(context).push<AutomationRecord>(
    MaterialPageRoute<AutomationRecord>(
      fullscreenDialog: true,
      builder: (_) => MobileAutomationAuthoringScreen(
        hostId: hostId,
        session: _nextSession++,
        initialDraft: draft,
        editing: editing,
      ),
    ),
  );
}

class MobileAutomationAuthoringScreen extends ConsumerStatefulWidget {
  const MobileAutomationAuthoringScreen({
    super.key,
    required this.hostId,
    required this.session,
    required this.initialDraft,
    this.editing,
  });

  final String hostId;
  final int session;
  final AutomationDraft initialDraft;
  final AutomationRecord? editing;

  @override
  ConsumerState<MobileAutomationAuthoringScreen> createState() =>
      _MobileAutomationAuthoringScreenState();
}

class _MobileAutomationAuthoringScreenState
    extends ConsumerState<MobileAutomationAuthoringScreen> {
  late final MobileAutomationAuthoringControllerProvider _provider =
      mobileAutomationAuthoringControllerProvider(
        widget.hostId,
        widget.session,
      );

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
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final saved = await ref.read(_provider.notifier).submit(asDraft: asDraft);
    if (saved == null || !mounted) return;
    ref.invalidate(mobileAutomationCatalogProvider(widget.hostId));
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          widget.editing != null
              ? 'Changes saved.'
              : asDraft
              ? 'Saved as a draft. Activate it when ready.'
              : saved.state == 'active'
              ? 'Automation created and active.'
              : 'Automation created.',
        ),
      ),
    );
    navigator.pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    final controller = ref.read(_provider.notifier);
    final step = state.step;
    final last = step == AutomationAuthoringStep.review;
    final error = state.showErrors ? state.stepError(step) : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.editing == null ? 'New Automation' : 'Edit Automation',
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.spaceLg,
              ),
              child: Text(
                'Step ${step.index + 1} Of 4 · ${step.label}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Expanded(
              child: !state.initialized
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: AleraTokens.pagePadding,
                      children: <Widget>[
                        switch (step) {
                          AutomationAuthoringStep.what => MobileWhatStep(
                            provider: _provider,
                          ),
                          AutomationAuthoringStep.when => MobileWhenStep(
                            provider: _provider,
                          ),
                          AutomationAuthoringStep.where => MobileWhereStep(
                            provider: _provider,
                            hostId: widget.hostId,
                          ),
                          AutomationAuthoringStep.review => MobileReviewStep(
                            provider: _provider,
                            hostId: widget.hostId,
                          ),
                        },
                      ],
                    ),
            ),
            // Beside the buttons, not under the step: a long step would push
            // the reason Continue did nothing below the fold.
            if (error ?? state.error case final message?)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AleraTokens.spaceLg,
                  AleraTokens.spaceSm,
                  AleraTokens.spaceLg,
                  0,
                ),
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AleraTokens.error),
                ),
              ),
            Padding(
              padding: AleraTokens.pagePadding,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: AleraTokens.spaceSm,
                runSpacing: AleraTokens.spaceSm,
                children: <Widget>[
                  if (step != AutomationAuthoringStep.what)
                    TextButton(
                      onPressed: controller.back,
                      child: const Text('Back'),
                    ),
                  if (last && widget.editing == null)
                    OutlinedButton(
                      onPressed: state.submitting
                          ? null
                          : () => unawaited(_submit(asDraft: true)),
                      child: const Text('Save As Draft'),
                    ),
                  FilledButton(
                    onPressed: state.submitting
                        ? null
                        : last
                        ? () => unawaited(_submit())
                        : controller.next,
                    child: Text(
                      !last
                          ? 'Continue'
                          : widget.editing == null
                          ? 'Create Automation'
                          : 'Save Changes',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
