part of 'codex_chat_surface.dart';

const EdgeInsets _codexTitledMenuPadding = .fromLTRB(
  AleraTokens.space12,
  AleraTokens.space4,
  AleraTokens.space12,
  AleraTokens.space12,
);

class const _CodexComposerControls({
  required final CodexChatState state,
  required final ValueChanged<String> onPermissionChanged,
  required final ValueChanged<bool> onPlanChanged,
  required final Future<void> Function() onAddAttachment,
  required final Future<void> Function() onPaste,
  required final ValueChanged<CodexDraftItem> onDraftItemSelected,
  required final ValueChanged<CodexComposerCommand> onCommand,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: .min,
    children: <Widget>[
      PopupMenuButton<String>(
        tooltip: 'Add Photos And Files',
        onSelected: (value) => _handleAddAction(context, value),
        itemBuilder: (context) => <PopupMenuEntry<String>>[
          const _CodexDropdownEntry<String>(
            value: 'file',
            label: 'Add Photos And Files',
            selected: false,
          ),
          const _CodexDropdownEntry<String>(
            value: 'paste',
            label: 'Paste From Clipboard',
            selected: false,
          ),
          const PopupMenuDivider(),
          const _CodexDropdownEntry<String>(
            value: 'skill',
            label: 'Add Skill',
            selected: false,
          ),
          const _CodexDropdownEntry<String>(
            value: 'app',
            label: 'Add App',
            selected: false,
          ),
          const PopupMenuDivider(),
          const _CodexDropdownEntry<String>(
            value: 'review',
            label: 'Start Review',
            selected: false,
          ),
          const _CodexDropdownEntry<String>(
            value: 'compact',
            label: 'Compact Context',
            selected: false,
          ),
          PopupMenuItem<String>(
            value: 'fork',
            enabled:
                state.supportsFork &&
                !state.historyLocked &&
                (state.snapshot.hasCompletedTurns ??
                    (state.historyNextCursor != null ||
                        state.snapshot.timelineCells.any(
                          (cell) =>
                              cell.turnId != null &&
                              cell.turnId != state.snapshot.activeTurnId,
                        ))),
            child: const Text('Fork Chat'),
          ),
          if (state.supportsSessions) ...const <PopupMenuEntry<String>>[
            PopupMenuDivider(),
            _CodexDropdownEntry<String>(
              value: 'resume',
              label: 'Resume Thread',
              selected: false,
            ),
            _CodexDropdownEntry<String>(
              value: 'new',
              label: 'Start New Chat',
              selected: false,
            ),
            _CodexDropdownEntry<String>(
              value: 'clear',
              label: 'Clear Chat',
              selected: false,
            ),
          ],
        ],
        child: const MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Padding(
            padding: EdgeInsets.all(AleraTokens.space4),
            child: Icon(
              AleraIcons.add,
              size: AleraTokens.iconXl,
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ),
      ),
      Theme(
        data: Theme.of(context).copyWith(highlightColor: Colors.transparent),
        child: PopupMenuButton<String>(
          tooltip: 'Choose Approval Mode',
          menuPadding: _codexTitledMenuPadding,
          constraints: const BoxConstraints(
            minWidth: AleraTokens.dialogCompactWidth,
            maxWidth: AleraTokens.dialogCompactWidth,
          ),
          color: AleraTokens.surfaceElevated,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            side: const BorderSide(color: AleraTokens.border),
          ),
          clipBehavior: .hardEdge,
          initialValue:
              state.permissionMode == 'on-request' ||
                  state.permissionMode == 'auto-review' &&
                      !state.supportsAutoReview
              ? 'untrusted'
              : state.permissionMode,
          onSelected: (value) => _selectPermission(context, value),
          itemBuilder: (context) => <PopupMenuEntry<String>>[
            _CodexMenuHeader('How Should Codex Actions Be Approved?'),
            _CodexPermissionEntry(
              value: 'untrusted',
              label: 'Ask For Approval',
              description:
                  'Always ask to edit external files and use the internet.',
              icon: AleraIcons.insecure,
              selected:
                  state.permissionMode == 'untrusted' ||
                  state.permissionMode == 'on-request' ||
                  state.permissionMode == 'auto-review' &&
                      !state.supportsAutoReview,
            ),
            if (state.supportsAutoReview)
              _CodexPermissionEntry(
                value: 'auto-review',
                label: 'Approve For Me',
                description:
                    'Only ask for actions detected as potentially unsafe.',
                icon: AleraIcons.secure,
                selected: state.permissionMode == 'auto-review',
              ),
            _CodexPermissionEntry(
              value: 'never',
              label: 'Full Access',
              description: 'Unrestricted access to the internet and any file on your computer.',
              icon: AleraIcons.warning,
              selected: state.permissionMode == 'never',
              warning: true,
            ),
          ],
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: _CodexComposerChip(
              label: state.permissionMode == 'never'
                  ? 'Full Access'
                  : state.permissionMode == 'auto-review' &&
                        state.supportsAutoReview
                  ? 'Approve For Me'
                  : 'Ask For Approval',
              highlight: state.permissionMode == 'never',
            ),
          ),
        ),
      ),
      InkWell(
        key: const ValueKey<String>('codex-plan-mode'),
        onTap: () => onPlanChanged(!state.planMode),
        mouseCursor: SystemMouseCursors.click,
        borderRadius: .circular(AleraTokens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AleraTokens.space2,
            AleraTokens.space4,
            AleraTokens.space8,
            AleraTokens.space4,
          ),
          child: Row(
            mainAxisSize: .min,
            children: <Widget>[
              Icon(
                state.planMode ? AleraIcons.planActive : AleraIcons.plan,
                size: AleraTokens.iconSm,
                color: state.planMode
                    ? AleraTokens.foreground
                    : AleraTokens.foregroundFaint,
              ),
              const SizedBox(width: AleraTokens.space4),
              Text(
                'Plan',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: state.planMode
                      ? AleraTokens.foreground
                      : AleraTokens.foregroundFaint,
                  fontWeight: state.planMode
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Future<void> _selectPermission(BuildContext context, String value) async {
    await _applyCodexPermissionSelection(context, value, onPermissionChanged);
  }

  Future<void> _handleAddAction(BuildContext context, String value) async {
    switch (value) {
      case 'fork':
        await context
            .findAncestorStateOfType<_CodexChatSurfaceState>()
            ?._forkHistory();
      case 'file':
        await onAddAttachment();
      case 'paste':
        await onPaste();
      case 'skill':
        await _pickCatalog(context, skill: true);
      case 'app':
        await _pickCatalog(context, skill: false);
      case 'review':
        onCommand(.review);
      case 'compact':
        onCommand(.compact);
      case 'resume':
        onCommand(.resume);
      case 'new':
        onCommand(.newChat);
      case 'clear':
        onCommand(.clear);
    }
  }

  Future<void> _pickCatalog(BuildContext context, {required bool skill}) async {
    final items = skill ? state.skills : state.apps;
    if (items.isEmpty) return;
    final selected = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => _CodexCatalogPickerDialog(
        title: skill ? 'Select A Skill' : 'Select An App',
        items: items,
        searchHint: skill ? 'Filter Skills' : 'Filter Apps',
      ),
    );
    if (selected == null) return;
    final name = _catalogName(selected);
    if (skill) {
      final path = selected['path']?.toString().trim() ?? '';
      if (path.isEmpty) return;
      onDraftItemSelected(
        CodexDraftItem(id: 'skill-$path', kind: .skill, name: name, path: path),
      );
      return;
    }
    final connector = _catalogConnector(selected);
    if (connector == null) return;
    onDraftItemSelected(
      CodexDraftItem(
        id: 'app-$connector',
        kind: .app,
        name: name,
        path: connector,
        tokenText: '\$$name',
        iconUrl: _catalogIconUrl(selected),
      ),
    );
  }
}

Future<void> _applyCodexPermissionSelection(
  BuildContext context,
  String value,
  ValueChanged<String> onSelected,
) async {
  if (value != 'never') {
    onSelected(value);
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => const _CodexFullAccessDialog(),
  );
  if (confirmed == true) onSelected(value);
}

class const _CodexComposerChip({
  required final String label,
  final String? secondaryLabel,
  final IconData? leadingIcon,
  final bool highlight = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AleraTokens.space8,
      vertical: AleraTokens.space4,
    ),
    child: Row(
      mainAxisSize: .min,
      children: <Widget>[
        if (leadingIcon case final IconData icon) ...<Widget>[
          Icon(icon, size: AleraTokens.iconXs, color: AleraTokens.foreground),
          const SizedBox(width: AleraTokens.space4),
        ],
        Flexible(
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(text: label, style: _labelStyle(context)),
                if (secondaryLabel case final String secondary
                    when secondary.isNotEmpty)
                  TextSpan(
                    text: ' $secondary',
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: AleraTokens.foregroundMuted),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: .ellipsis,
          ),
        ),
        const SizedBox(width: AleraTokens.space4),
        const Icon(
          AleraIcons.chevronDown,
          size: AleraTokens.iconMd,
          color: AleraTokens.foregroundFaint,
        ),
      ],
    ),
  );

  TextStyle? _labelStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelMedium?.copyWith(
        color: highlight
            ? AleraTokens.warning
            : secondaryLabel == null
            ? AleraTokens.foregroundMuted
            : AleraTokens.foreground,
      );
}

class _CodexMenuHeader extends PopupMenuItem<String> {
  new(String label)
    : super(
        enabled: false,
        height: AleraTokens.space24,
        padding: const .symmetric(horizontal: AleraTokens.space8),
        child: Text(label, style: AleraTokens.labelFaintStyle),
      );
}

String? _catalogConnector(Map<String, Object?> item) {
  final path = item['path']?.toString().trim();
  if (path != null && path.startsWith('app://')) return path;
  for (final key in <String>['connectorId', 'connector_id', 'appId', 'id']) {
    final value = item[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return 'app://$value';
  }
  return null;
}

String _choiceLabel(String value) => value
    .split('-')
    .map(
      (part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');
