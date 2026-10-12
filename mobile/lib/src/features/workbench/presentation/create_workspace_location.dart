part of 'create_workspace_screen.dart';

extension _CreateWorkspaceLocation on _CreateWorkspaceScreenState {
  Widget _locationSelector({required String? projectId, bool enabled = true}) {
    final supportsWorktree = widget.projects.any(
      (project) => project.id == projectId && project.supportsLinkedWorkspaces,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (projectId != null) ...[
            _checkoutHostSelector(projectId, enabled),
            const SizedBox(height: AleraTokens.spaceMd),
          ],
          if (!widget.supportsSharedCheckoutWorkspaces)
            const Text(
              'Update Alera on this host to create tasks in the project folder.',
            ),
          SegmentedButton<bool>(
            segments: <ButtonSegment<bool>>[
              ButtonSegment(
                value: true,
                label: const Text('Project Folder'),
                enabled: widget.supportsSharedCheckoutWorkspaces,
              ),
              ButtonSegment(
                value: false,
                label: const Text('New Worktree'),
                enabled: supportsWorktree,
              ),
            ],
            selected: <bool>{_useProjectCheckout},
            onSelectionChanged: enabled
                ? (selection) {
                    _update(() => _useProjectCheckout = selection.single);
                    if (projectId == null) return;
                    if (_fromPrompt) {
                      unawaited(
                        ref
                            .read(
                              promptWorkspaceControllerProvider(widget.hostId)
                                  .notifier,
                            )
                            .selectProject(
                              projectId,
                              defaultAgentProfileId:
                                  widget.defaultAgentProfileId,
                              loadBranches: !_useProjectCheckout,
                              checkoutHostId: _checkoutHostId,
                            ),
                      );
                    } else {
                      unawaited(_selectProject(projectId));
                    }
                  }
                : null,
          ),
        ],
      ),
    );
  }

  bool _checkoutReady(String? projectId) {
    if (projectId == null ||
        (_useProjectCheckout && !widget.supportsSharedCheckoutWorkspaces)) {
      return false;
    }
    final checkoutHostId = _checkoutHostId ?? 'local';
    final registered =
        ref
            .read(workspaceCheckoutOptionsProvider(widget.hostId, projectId))
            .value
            ?.any((checkout) => checkout.hostId == checkoutHostId) ??
        false;
    return registered && (_workspaceHostOf(checkoutHostId)?.isReady ?? true);
  }

  /// The directory entry for a checkout host, or null for the paired device
  /// and for a runtime that does not name its hosts.
  MobileWorkspaceHost? _workspaceHostOf(String checkoutHostId) {
    if (checkoutHostId == 'local') return null;
    return ref
        .read(workspaceHostsControllerProvider(widget.hostId))
        .value
        ?.byId[checkoutHostId];
  }

  AleraDropdownFieldEntry<String> _checkoutHostEntry(
    ProjectCheckoutSummary checkout,
    MobileWorkspaceHostDirectory? directory,
  ) {
    if (checkout.hostId == 'local') {
      return AleraDropdownFieldEntry(
        value: checkout.hostId,
        label: checkout.label,
        leading: const Icon(
          AleraIcons.pairedDevices,
          size: AleraTokens.rowMetaIcon,
          color: AleraTokens.foregroundMuted,
        ),
      );
    }
    final host = directory?.byId[checkout.hostId];
    return AleraDropdownFieldEntry(
      value: checkout.hostId,
      label: host?.pickerLabel ?? checkout.label,
      leading: AleraHostOsIcon(
        os: host?.os ?? HostOs.unknown,
        size: AleraTokens.rowMetaIcon,
      ),
      enabled: host?.isReady ?? true,
    );
  }

  Widget? _checkoutHostNotice(MobileWorkspaceHost? host) {
    final notice = host?.pickerNotice;
    if (notice == null) return null;
    return Padding(
      padding: const EdgeInsets.only(top: AleraTokens.spaceXs),
      child: Text(
        notice.message,
        key: const Key('checkout-host-notice'),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: notice.blocksCreation
              ? AleraTokens.error
              : AleraTokens.foregroundMuted,
        ),
      ),
    );
  }

  Widget _checkoutHostSelector(String projectId, bool enabled) {
    final hostId =
        ref.watch(
          workspaceCheckoutSelectionProvider(
            widget.hostId,
            widget.initialCheckoutHostId,
          ),
        ) ??
        'local';
    final options = ref.watch(
      workspaceCheckoutOptionsProvider(widget.hostId, projectId),
    );
    final directory = ref
        .watch(workspaceHostsControllerProvider(widget.hostId))
        .value;
    return options.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => Text('Could not load project locations: $error'),
      data: (checkouts) {
        final selected = checkouts.any((checkout) => checkout.hostId == hostId)
            ? hostId
            : null;
        final notice = selected == null
            ? null
            : _checkoutHostNotice(_workspaceHostOf(selected));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _checkoutHostField(
              projectId: projectId,
              selected: selected,
              entries: [
                for (final checkout in checkouts)
                  _checkoutHostEntry(checkout, directory),
              ],
              enabled: enabled,
            ),
            ?notice,
          ],
        );
      },
    );
  }

  Widget _checkoutHostField({
    required String projectId,
    required String? selected,
    required List<AleraDropdownFieldEntry<String>> entries,
    required bool enabled,
  }) {
    return AleraDropdownField<String>(
      value: selected,
      labelText: 'Host',
      hintText: 'Select Registered Project Location',
      entries: entries,
      enabled: enabled,
      onChanged: (value) {
        ref
            .read(
              workspaceCheckoutSelectionProvider(
                widget.hostId,
                widget.initialCheckoutHostId,
              ).notifier,
            )
            .select(value);
        if (_fromPrompt) {
          unawaited(
            ref
                .read(promptWorkspaceControllerProvider(widget.hostId).notifier)
                .selectProject(
                  projectId,
                  loadBranches: !_useProjectCheckout,
                  checkoutHostId: _checkoutHostId,
                  defaultAgentProfileId: widget.defaultAgentProfileId,
                ),
          );
        } else {
          unawaited(_selectProject(projectId));
        }
      },
    );
  }

  void _selectPromptProject(
    String projectId,
    PromptWorkspaceController controller,
  ) {
    _update(() {
      _promptParentWorkspaceId = null;
      if (!widget.projects.any(
        (project) =>
            project.id == projectId && project.supportsLinkedWorkspaces,
      )) {
        _useProjectCheckout = true;
      } else if (!widget.supportsSharedCheckoutWorkspaces) {
        _useProjectCheckout = false;
      }
    });
    controller.selectProject(
      projectId,
      loadBranches: !_useProjectCheckout,
      checkoutHostId: _checkoutHostId,
      defaultAgentProfileId: widget.defaultAgentProfileId,
    );
  }
}
