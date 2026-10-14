part of 'workspace_details_overlay.dart';

const String _openAutomationsMenuValue = '__open-automations';
const String _newAutomationMenuValue = '__new-automation';

/// Live automations associated with the workspace, by name. Completed and
/// trashed ones stay in the catalog but not on the card.
List<AutomationRecord> _workspaceAutomations(
  List<AutomationRecord>? catalog,
  String workspaceId,
) {
  final scope = AutomationScope(
    kind: AutomationScopeKind.workspace,
    id: workspaceId,
  );
  return [
    for (final automation in catalog ?? const <AutomationRecord>[])
      if (scope.includes(automation) &&
          !automation.isTrashed &&
          !automation.isCompleted)
        automation,
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

/// The run the row reports: one still in progress wins, since it is the
/// newest run of its automation, else the most recently finished one.
AutomationLastRun? _latestRun(List<AutomationRecord> automations) {
  AutomationLastRun? latest;
  for (final automation in automations) {
    final run = automation.lastRun;
    if (run == null) continue;
    final finished = run.finishedAt;
    if (finished == null) return run;
    final current = latest?.finishedAt;
    if (current == null || finished.isAfter(current)) latest = run;
  }
  return latest;
}

extension on _WorkspaceDetailsOverlayState {
  AutomationScope get _automationScope => AutomationScope(
    kind: AutomationScopeKind.workspace,
    id: widget.workspace.id,
  );

  AleraWorkspaceDetailRow? _automationsRow(List<AutomationRecord> automations) {
    if (automations.isEmpty) return null;
    final latest = _latestRun(automations);
    return AleraWorkspaceDetailRow(
      label: automations.length == 1
          ? automations.single.name
          : '${automations.length} Automations',
      subtitle: latest == null ? 'No runs yet' : automationLastRunLabel(latest),
      subtitleColor: latest == null
          ? null
          : automationToneColor(automationRunStatusTone(latest.status)),
      leading: const Icon(AleraIcons.checks),
      hint: 'Open this workspace\'s automations',
      onPressed: _openAutomations,
      onMenu: (anchor) => unawaited(_automationsMenu(anchor, automations)),
    );
  }

  void _openAutomations([String? automationId]) {
    final navigation = ref.read(activityNavigationProvider.notifier)
      ..openAutomations(scope: _automationScope);
    if (automationId != null) navigation.selectAutomation(automationId);
  }

  void _newAutomation() => ref
      .read(activityNavigationProvider.notifier)
      .startAuthoring(
        AutomationAuthoringRequest(
          originWorkspaceId: widget.workspace.id,
          sectionId: widget.workspace.sectionId,
        ),
        scope: _automationScope,
      );

  Future<void> _automationsMenu(
    Rect anchor,
    List<AutomationRecord> automations,
  ) async {
    final choice = await _menu(anchor, [
      for (final automation in automations)
        AleraDropdownEntry(
          value: automation.id,
          label: automation.name,
          detail: automation.lastRun == null
              ? automation.state == 'active'
                    ? null
                    : automationStateLabel(automation).label
              : automationLastRunLabel(automation.lastRun!),
          leading: const _MenuIcon(AleraIcons.checks),
        ),
      const PopupMenuDivider(),
      const AleraDropdownEntry(
        value: _openAutomationsMenuValue,
        label: 'Open Automations',
        leading: _MenuIcon(AleraIcons.external),
      ),
      const AleraDropdownEntry(
        value: _newAutomationMenuValue,
        label: 'New Automation Here',
        leading: _MenuIcon(AleraIcons.add),
      ),
    ]);
    if (!mounted || choice == null) return;
    switch (choice) {
      case _openAutomationsMenuValue:
        _openAutomations();
      case _newAutomationMenuValue:
        _newAutomation();
      default:
        _openAutomations(choice);
    }
  }
}
