import 'dart:async';

import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_composer_controller.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_composer_defaults.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_context.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/automations/presentation/composer/mobile_automation_composer_form.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_confirmations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

int _nextComposerSession = 0;

/// Opens the composer to create, edit or clone an automation and returns
/// the saved definition. Saving closes the composer and never opens another
/// screen; the caller decides what to show.
Future<AutomationRecord?> showMobileAutomationComposer(
  BuildContext context, {
  required String hostId,
  String? originWorkspaceId,
  AutomationRecord? editing,
  AutomationRecord? cloneOf,
}) => Navigator.of(context).push<AutomationRecord>(
  MaterialPageRoute<AutomationRecord>(
    fullscreenDialog: true,
    builder: (_) => MobileAutomationComposerScreen(
      hostId: hostId,
      session: _nextComposerSession++,
      originWorkspaceId: originWorkspaceId,
      editing: editing,
      cloneOf: cloneOf,
    ),
  ),
);

class MobileAutomationComposerScreen extends ConsumerStatefulWidget {
  const MobileAutomationComposerScreen({
    super.key,
    required this.hostId,
    required this.session,
    this.originWorkspaceId,
    this.editing,
    this.cloneOf,
  });

  final String hostId;
  final int session;

  /// The workspace the composer was opened from, which seeds a new tab there.
  final String? originWorkspaceId;
  final AutomationRecord? editing;
  final AutomationRecord? cloneOf;

  @override
  ConsumerState<MobileAutomationComposerScreen> createState() =>
      _MobileAutomationComposerScreenState();
}

class _MobileAutomationComposerScreenState
    extends ConsumerState<MobileAutomationComposerScreen> {
  late final MobileAutomationComposerControllerProvider _provider =
      mobileAutomationComposerControllerProvider(widget.hostId, widget.session);
  bool _seeded = false;
  bool _closing = false;

  /// Seeds once the names are known: a new automation needs the origin
  /// workspace and the profiles; an edit or a clone starts from its record.
  void _maybeSeed(AsyncValue<MobileAutomationContext> names) {
    final fromRecord = widget.editing ?? widget.cloneOf;
    if (_seeded || (fromRecord == null && names.isLoading)) return;
    _seeded = true;
    final draft = switch ((widget.editing, widget.cloneOf)) {
      (final AutomationRecord editing, _) => AutomationDraft.fromRecord(
        editing,
      ),
      (_, final AutomationRecord clone) => AutomationDraft.fromRecord(
        clone,
      ).cloned(),
      _ => seedMobileAutomationDraft(
        names.value ?? const MobileAutomationContext(),
        originWorkspaceId: widget.originWorkspaceId,
        lastProfileId: ref.read(
          mobileAutomationLastAgentProfileProvider(widget.hostId),
        ),
      ),
    };
    // Providers cannot change while the tree builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(_provider.notifier).initialize(draft, editing: widget.editing);
    });
  }

  Future<void> _requestClose() async {
    if (_closing) return;
    if (ref.read(_provider).isDirty) {
      _closing = true;
      final discard = await confirmMobileAutomationDiscard(context);
      _closing = false;
      if (!discard || !mounted) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _submit({bool asDraft = false, bool activate = false}) async {
    final state = ref.read(_provider);
    if (state.submitting) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final editing = state.editing;
    final saved = await ref
        .read(_provider.notifier)
        .submit(asDraft: asDraft, activate: activate);
    if (saved == null || !mounted) return;
    ref.invalidate(mobileAutomationCatalogProvider(widget.hostId));
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch ((editing != null, asDraft, saved.state)) {
          (true, _, _) when activate => 'Changes saved and active.',
          (true, _, _) => 'Changes saved.',
          (false, true, _) => 'Saved as a draft. Activate it when ready.',
          (false, false, 'active') => 'Automation created and active.',
          _ => 'Automation created.',
        }),
      ),
    );
    navigator.pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final names = ref.watch(mobileAutomationContextProvider(widget.hostId));
    // Kept alive for the whole session so every request reuses it.
    ref.watch(mobileAutomationRepositoryProvider(widget.hostId));
    _maybeSeed(names);
    final state = ref.watch(_provider);
    final editing = state.editing;
    final blocked = state.submitting || state.readinessBlocks;
    // Editing a draft keeps it a draft; activating is the explicit primary.
    final (String primaryLabel, VoidCallback? primary) = editing == null
        ? ('Create And Activate', blocked ? null : () => _submit())
        : state.editsDraft
        ? ('Save And Activate', blocked ? null : () => _submit(activate: true))
        : ('Save Changes', blocked ? null : () => _submit());
    final secondary = editing == null
        ? OutlinedButton(
            onPressed: state.submitting
                ? null
                : () => unawaited(_submit(asDraft: true)),
            child: const Text('Save As Draft'),
          )
        : state.editsDraft
        ? OutlinedButton(
            onPressed: state.submitting ? null : () => unawaited(_submit()),
            child: const Text('Save Changes'),
          )
        : null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(AleraIcons.close),
            onPressed: () => unawaited(_requestClose()),
          ),
          title: Text(
            widget.editing == null ? 'New Automation' : 'Edit Automation',
          ),
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: .stretch,
            children: <Widget>[
              Expanded(
                child: !state.initialized
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: AleraTokens.pagePadding,
                        child: MobileAutomationComposerForm(
                          provider: _provider,
                          hostId: widget.hostId,
                        ),
                      ),
              ),
              Padding(
                padding: AleraTokens.pagePadding,
                child: Row(
                  children: <Widget>[
                    if (secondary != null) Expanded(child: secondary),
                    if (secondary != null)
                      const SizedBox(width: AleraTokens.spaceSm),
                    Expanded(
                      child: FilledButton(
                        onPressed: primary,
                        child: Text(primaryLabel),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
