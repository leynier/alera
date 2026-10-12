import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/forms/alera_command_enter_shortcuts.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/features/automations/application/automation_composer_controller.dart';
import 'package:alera/src/features/automations/application/automation_composer_defaults.dart';
import 'package:alera/src/features/automations/application/automation_providers.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/automations/presentation/automation_destructive_actions.dart';
import 'package:alera/src/features/automations/presentation/composer/automation_composer_form.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

int _nextComposerSession = 0;

/// Opens the composer to create, edit or clone an automation. Returns the
/// saved definition, which the Automations page then selects.
Future<AutomationRecord?> showAutomationComposerDialog(
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
  final names = ref.read(automationWorkbenchContextProvider);
  final draft = editing != null
      ? AutomationDraft.fromRecord(editing)
      : cloned != null
      ? AutomationDraft.fromRecord(cloned).cloned()
      : seedAutomationComposerDraft(
          request,
          names,
          profileId: automationPreferredProfileId(
            names.profiles,
            lastUsed: ref.read(automationLastAgentProfileProvider),
            settingsDefault: ref
                .read(settingsControllerProvider)
                .agents
                .defaultAgentProfileId,
          ),
        );
  final saved = await showDialog<AutomationRecord>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AutomationComposerDialog(
      session: _nextComposerSession++,
      initialDraft: draft,
      editing: editing,
      seedProjectId: editing == null && cloned == null
          ? request.projectId
          : null,
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

class AutomationComposerDialog extends ConsumerStatefulWidget {
  const AutomationComposerDialog({
    super.key,
    required this.session,
    required this.initialDraft,
    this.editing,
    this.seedProjectId,
  });

  final int session;
  final AutomationDraft initialDraft;
  final AutomationRecord? editing;
  final String? seedProjectId;

  @override
  ConsumerState<AutomationComposerDialog> createState() =>
      _AutomationComposerDialogState();
}

class _AutomationComposerDialogState
    extends ConsumerState<AutomationComposerDialog> {
  late final AutomationComposerControllerProvider _provider =
      automationComposerControllerProvider(widget.session);
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    // Providers cannot change while the tree builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(_provider.notifier)
          .initialize(
            widget.initialDraft,
            editing: widget.editing,
            seedProjectId: widget.seedProjectId,
          );
    });
  }

  Future<void> _requestClose() async {
    if (_closing) return;
    if (ref.read(_provider).isDirty) {
      _closing = true;
      final discard = await confirmAutomationDiscard(context);
      _closing = false;
      if (!discard || !mounted) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _submit({bool asDraft = false, bool activate = false}) async {
    final state = ref.read(_provider);
    if (state.submitting) return;
    final editing = state.editing;
    final saved = await ref
        .read(_provider.notifier)
        .submit(asDraft: asDraft, activate: activate);
    if (saved == null || !mounted) return;
    AleraToast.publish(
      message: switch ((editing != null, asDraft, saved.state)) {
        (true, _, 'active') when activate => 'Changes saved and active.',
        (true, _, _) => 'Changes saved.',
        (false, true, _) => 'Saved as a draft. Activate it when ready.',
        (false, false, 'active') => 'Automation created and active.',
        _ => 'Automation created.',
      },
      tone: AleraToastTone.success,
    );
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    final editing = state.editing;
    final blocked = state.submitting || state.readinessBlocks;
    // Editing a draft keeps it a draft; activating is the explicit primary.
    final (String primaryLabel, VoidCallback? primary) = editing == null
        ? ('Create And Activate', blocked ? null : () => _submit())
        : state.editsDraft
        ? ('Save And Activate', blocked ? null : () => _submit(activate: true))
        : ('Save Changes', blocked ? null : () => _submit());
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            unawaited(_requestClose()),
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_requestClose());
        },
        child: AleraCommandEnterShortcuts(
          onCommandEnter: primary,
          child: AleraDialog(
            maxWidth: AleraTokens.automationAuthoringWidth,
            maxHeight: AleraTokens.automationAuthoringMaxHeight,
            child: Padding(
              padding: const EdgeInsets.all(AleraTokens.space20),
              child: Column(
                crossAxisAlignment: .stretch,
                children: <Widget>[
                  AleraDialogHeader(
                    title: editing == null
                        ? 'New Automation'
                        : 'Edit Automation',
                    onClose: () => unawaited(_requestClose()),
                  ),
                  const SizedBox(height: AleraTokens.space12),
                  Flexible(
                    child: !state.initialized
                        ? const Center(child: CircularProgressIndicator())
                        : SingleChildScrollView(
                            padding: const EdgeInsets.only(
                              right: AleraTokens.space8,
                            ),
                            child: AutomationComposerForm(
                              provider: _provider,
                              onSubmit: primary,
                            ),
                          ),
                  ),
                  const SizedBox(height: AleraTokens.space16),
                  Row(
                    children: <Widget>[
                      if (editing == null)
                        OutlinedButton(
                          onPressed: state.submitting
                              ? null
                              : () => unawaited(_submit(asDraft: true)),
                          child: const Text('Save As Draft'),
                        ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => unawaited(_requestClose()),
                        child: const Text('Cancel'),
                      ),
                      if (state.editsDraft) ...<Widget>[
                        const SizedBox(width: AleraTokens.space8),
                        OutlinedButton(
                          onPressed: state.submitting
                              ? null
                              : () => unawaited(_submit()),
                          child: const Text('Save Changes'),
                        ),
                      ],
                      const SizedBox(width: AleraTokens.space8),
                      FilledButton(
                        onPressed: primary,
                        child: Text(primaryLabel),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
